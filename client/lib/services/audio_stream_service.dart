import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'websocket_service.dart';

class AudioStreamService {
  static const _methodChannel = MethodChannel('vaia/audio');

  final WebSocketService _ws;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<List<int>>? _sub;

  // 500ms @ 16kHz 16-bit mono = 16,000 bytes
  static const _chunkBytes = 16000;
  final List<int> _buffer = [];

  AudioStreamService(this._ws);

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

    _sub = stream.listen((chunk) {
      _buffer.addAll(chunk);
      while (_buffer.length >= _chunkBytes) {
        final toSend = _buffer.sublist(0, _chunkBytes);
        _buffer.removeRange(0, _chunkBytes);
        _ws.sendAudio(toSend);
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _buffer.clear();
    await _recorder.stop();

    if (Platform.isAndroid) {
      await _methodChannel.invokeMethod('disableSpeaker');
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}
