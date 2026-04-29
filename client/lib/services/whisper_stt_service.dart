import 'dart:io';
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

  void dispose() => _whisper = null;
}
