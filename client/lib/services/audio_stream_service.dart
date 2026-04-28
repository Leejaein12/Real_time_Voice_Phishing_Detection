import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'websocket_service.dart';

class AudioStreamService {
  static const _methodChannel = MethodChannel('vaia/audio');
  static const _eventChannel = EventChannel('vaia/phone_state');

  final WebSocketService _ws;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<int>>? _audioSub;
  StreamSubscription<dynamic>? _phoneSub;

  // 500ms @ 16kHz 16-bit mono = 16,000 bytes
  static const _chunkBytes = 16000;
  final List<int> _buffer = [];

  VoidCallback? onCallStarted;
  VoidCallback? onCallConnected;
  VoidCallback? onCallEnded;
  void Function(String)? onIncomingNumber;

  AudioStreamService(this._ws);

  void startPhoneEventListening() {
    if (!Platform.isAndroid) return;
    _phoneSub = _eventChannel.receiveBroadcastStream().listen(_handlePhoneEvent);
    // 앱이 닫혀 있을 때 수신된 전화 상태 복원 (타이밍 문제 해결)
    _checkPendingCallState();
  }

  void _handlePhoneEvent(dynamic event) {
    final data = Map<String, dynamic>.from(event as Map);
    final state = data['state'] as String?;
    final number = data['number'] as String? ?? '';
    switch (state) {
      case 'ringing':
        if (number.isNotEmpty) onIncomingNumber?.call(number);
        onCallStarted?.call();
      case 'offhook':
        onCallConnected?.call();
      case 'idle':
        onCallEnded?.call();
    }
  }

  // 앱 시작 시 Flutter가 준비되기 전에 발생한 전화 이벤트 복원
  Future<void> _checkPendingCallState() async {
    try {
      final result = await _methodChannel
          .invokeMethod<Map<Object?, Object?>>('getPendingCallState');
      if (result == null) return;
      final state = result['state'] as String?;
      if (state == null || state == 'idle') return;
      // 복원한 뒤 즉시 삭제 (중복 처리 방지)
      await _methodChannel.invokeMethod('clearPendingCallState');
      _handlePhoneEvent({'state': state, 'number': result['number'] ?? ''});
    } catch (_) {}
  }

  Future<void> start() async {
    if (!await _recorder.hasPermission()) return;
    if (Platform.isAndroid) {
      await _methodChannel.invokeMethod('enableSpeaker');
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _audioSub = stream.listen((chunk) {
      _buffer.addAll(chunk);
      while (_buffer.length >= _chunkBytes) {
        final toSend = _buffer.sublist(0, _chunkBytes);
        _buffer.removeRange(0, _chunkBytes);
        _ws.sendAudio(toSend);
      }
    });
  }

  Future<void> stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    _buffer.clear();
    await _recorder.stop();
    if (Platform.isAndroid) {
      await _methodChannel.invokeMethod('disableSpeaker');
    }
  }

  Future<Map<String, bool>> checkPermissions() async {
    if (!Platform.isAndroid) return {};
    final result = await _methodChannel
        .invokeMethod<Map<Object?, Object?>>('checkPermissions');
    return result?.map((k, v) => MapEntry(k.toString(), v as bool)) ?? {};
  }

  Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    await _methodChannel.invokeMethod('openBatterySettings');
  }

  Future<void> openOverlaySettings() async {
    if (!Platform.isAndroid) return;
    await _methodChannel.invokeMethod('openOverlaySettings');
  }

  void dispose() {
    _phoneSub?.cancel();
    _recorder.dispose();
  }
}
