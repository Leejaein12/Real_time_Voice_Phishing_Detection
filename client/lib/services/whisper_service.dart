import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WhisperService {
  static const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';
  final String _apiKey;

  WhisperService(this._apiKey);

  bool _hasSpeech(Uint8List pcm) {
    if (pcm.length < 2) return false;
    double sum = 0;
    for (var i = 0; i < pcm.length - 1; i += 2) {
      final sample = (pcm[i + 1] << 8) | pcm[i];
      final signed = sample > 32767 ? sample - 65536 : sample;
      sum += signed * signed;
    }
    final rms = sum / (pcm.length / 2);
    debugPrint('[VAD] rms=$rms');
    return rms > 500;
  }

  Future<String> transcribe(Uint8List pcm) async {
    if (_apiKey.isEmpty) return '';
    if (!_hasSpeech(pcm)) {
      debugPrint('[Whisper] VAD 통과 안됨 - 스킵');
      return '';
    }

    try {
      final wav = _toWav(pcm);
      final req = http.MultipartRequest('POST', Uri.parse(_endpoint))
        ..headers['Authorization'] = 'Bearer $_apiKey'
        ..fields['model'] = 'whisper-1'
        ..fields['language'] = 'ko'
        ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'audio.wav'));

      final res = await req.send().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return '';

      final body = await res.stream.bytesToString();
      return (jsonDecode(body)['text'] as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Uint8List _toWav(Uint8List pcm) {
    const sampleRate = 16000;
    const numChannels = 1;
    const bitsPerSample = 16;
    final data = ByteData(44);

    void setStr(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    setStr(0, 'RIFF');
    data.setUint32(4, 36 + pcm.length, Endian.little);
    setStr(8, 'WAVE');
    setStr(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * numChannels * bitsPerSample ~/ 8, Endian.little);
    data.setUint16(32, numChannels * bitsPerSample ~/ 8, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    setStr(36, 'data');
    data.setUint32(40, pcm.length, Endian.little);

    final wav = Uint8List(44 + pcm.length);
    wav.setRange(0, 44, data.buffer.asUint8List());
    wav.setRange(44, 44 + pcm.length, pcm);
    return wav;
  }
}
