import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

export 'package:whisper_flutter_new/whisper_flutter_new.dart'
    show WhisperTranscribeResponse, WhisperTranscribeSegment;

/// whisper.cpp 기반 온디바이스 STT 서비스
/// 모델: ggml-base (142MB) — 첫 실행 시 다운로드 필요
class WhisperSttService {
  WhisperSttService._();
  static final instance = WhisperSttService._();

  static const _modelFileName = 'ggml-base.bin';
  static const _modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$_modelFileName';

  Whisper? _whisper;
  bool get isReady => _whisper != null;

  Future<String> _getModelDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  Future<String> _getModelPath() async =>
      '${await _getModelDir()}/$_modelFileName';

  Future<bool> isModelDownloaded() async =>
      File(await _getModelPath()).existsSync();

  /// 모델 다운로드 (466MB, 최초 1회)
  /// [onProgress] : 0.0 ~ 1.0
  Future<void> downloadModel({void Function(double progress)? onProgress}) async {
    final path = await _getModelPath();
    if (File(path).existsSync()) return;

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(_modelUrl));
      final resp = await client.send(req);
      final total = resp.contentLength ?? 0;
      var received = 0;

      final sink = File(path).openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } catch (e) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 모델 초기화 — downloadModel() 완료 후 호출
  Future<void> initialize() async {
    if (!await isModelDownloaded()) {
      throw StateError('모델 파일 없음. downloadModel()을 먼저 호출하세요.');
    }
    _whisper = Whisper(
      model: WhisperModel.base,
      modelDir: await _getModelDir(),
    );
  }

  /// assets 파일을 임시 디렉토리에 복사 후 경로 반환
  Future<String> copyAssetToTemp(String assetPath) async {
    final tmp = await getTemporaryDirectory();
    final name = assetPath.split('/').last;
    final out = '${tmp.path}/$name';
    final data = await rootBundle.load(assetPath);
    await File(out).writeAsBytes(data.buffer.asUint8List());
    return out;
  }

  /// WAV 파일 → 한국어 STT
  /// 반환: text + segments(fromTs/toTs 타임스탬프 포함)
  Future<WhisperTranscribeResponse> transcribe(String wavPath) async {
    if (_whisper == null) throw StateError('initialize()를 먼저 호출하세요.');
    return _whisper!.transcribe(
      transcribeRequest: TranscribeRequest(
        audio: wavPath,
        language: 'ko',
        isTranslate: false,
        isNoTimestamps: false,
      ),
    );
  }

  /// PCM 청크를 임시 WAV 파일로 변환 후 STT 처리하여 텍스트 반환
  Future<String> transcribeChunk(Uint8List pcmBytes,
      {int sampleRate = 16000}) async {
    if (_whisper == null) throw StateError('initialize()를 먼저 호출하세요.');
    final tmp = await getTemporaryDirectory();
    final chunkPath =
        '${tmp.path}/chunk_${DateTime.now().millisecondsSinceEpoch}.wav';

    final wavFile = File(chunkPath);
    final sink = wavFile.openWrite();
    sink.add(_buildWavHeader(pcmBytes.length, sampleRate));
    sink.add(pcmBytes);
    await sink.close();

    try {
      final response = await _whisper!.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: chunkPath,
          language: 'ko',
          isTranslate: false,
          isNoTimestamps: true,
        ),
      );
      return response.text.trim();
    } finally {
      if (wavFile.existsSync()) wavFile.deleteSync();
    }
  }

  Uint8List _buildWavHeader(int pcmLength, int sampleRate) {
    final bd = ByteData(44);
    void s(int off, String str) {
      for (var i = 0; i < str.length; i++) {
        bd.setUint8(off + i, str.codeUnitAt(i));
      }
    }
    s(0, 'RIFF');
    bd.setUint32(4, pcmLength + 36, Endian.little);
    s(8, 'WAVE');
    s(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);           // PCM
    bd.setUint16(22, 1, Endian.little);           // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little); // byteRate
    bd.setUint16(32, 2, Endian.little);           // blockAlign
    bd.setUint16(34, 16, Endian.little);          // bitsPerSample
    s(36, 'data');
    bd.setUint32(40, pcmLength, Endian.little);
    return bd.buffer.asUint8List();
  }

  void dispose() => _whisper = null;
}
