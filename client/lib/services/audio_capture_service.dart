import 'dart:async';
import 'package:flutter/services.dart';

class AudioCaptureService {
  static const _method = MethodChannel('vaia/audio');
  static const _event = EventChannel('vaia/audioStream');

  static const _sampleRate = 16000;
  static const _bytesPerSample = 2;
  static const _chunkSeconds = 2;
  static const _chunkSize = _sampleRate * _bytesPerSample * _chunkSeconds;

  StreamSubscription? _sub;
  final List<int> _buf = [];
  Function(Uint8List)? _onChunk;

  Future<bool> start(Function(Uint8List pcm) onChunk) async {
    _onChunk = onChunk;
    _buf.clear();

    final ok = await _method.invokeMethod<bool>('startCapture') ?? false;
    if (!ok) return false;

    _sub = _event.receiveBroadcastStream().listen((data) {
      if (data is Uint8List) {
        _buf.addAll(data);
        while (_buf.length >= _chunkSize) {
          final chunk = Uint8List.fromList(_buf.sublist(0, _chunkSize));
          _buf.removeRange(0, _chunkSize);
          _onChunk?.call(chunk);
        }
      }
    });

    return true;
  }

  Future<void> stop() async {
    _sub?.cancel();
    _sub = null;
    _buf.clear();
    await _method.invokeMethod('stopCapture');
  }
}
