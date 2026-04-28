import 'package:flutter/foundation.dart';
import '../models/analysis_result.dart';
import '../config.dart';
import 'audio_capture_service.dart';
import 'whisper_service.dart';
import 'nlu_service.dart';
import 'llm_service.dart';

class SttService {
  final AudioCaptureService _capture = AudioCaptureService();
  final WhisperService _whisper = WhisperService(AppConfig.anthropicApiKey);
  final NluService _nlu = NluService();
  final LlmService _llm = LlmService(AppConfig.anthropicApiKey);

  Function(AnalysisResult)? _onResult;
  Function(String)? _onExplanation;
  Function(String)? _onStatus;
  bool _active = false;
  bool _transcribing = false;
  final List<String> _textWindow = [];

  Future<bool> start(
    Function(AnalysisResult) onResult, {
    Function(String)? onExplanation,
    Function(String)? onStatus,
  }) async {
    _onResult = onResult;
    _onExplanation = onExplanation;
    _onStatus = onStatus;
    _active = true;
    _textWindow.clear();

    _onStatus?.call('모델 로딩 중...');
    await _nlu.init();

    _onStatus?.call('마이크 연결 중...');
    final ok = await _capture.start(_onAudioChunk);
    if (!ok) {
      debugPrint('[STT] AudioRecord 시작 실패');
      _onStatus?.call('마이크 연결 실패');
      return false;
    }

    _onStatus?.call('음성 감지 중...');
    debugPrint('[STT] 오디오 캡처 시작');
    return true;
  }

  Future<void> _onAudioChunk(Uint8List pcm) async {
    if (!_active || _transcribing) return;
    _transcribing = true;

    try {
      _onStatus?.call('음성 분석 중...');
      final text = await _whisper.transcribe(pcm);
      debugPrint('[STT] 인식: $text');

      if (text.isEmpty) {
        _onStatus?.call('음성 감지 중...');
        return;
      }

      _textWindow.add(text);
      if (_textWindow.length > 10) _textWindow.removeAt(0);

      final windowText = _textWindow.join(' ');
      final analysis = _nlu.analyze(windowText);
      _onResult?.call(analysis);

      if (analysis.warningLevel >= 1 && analysis.detectedLabels.isNotEmpty) {
        _llm
            .explain(
              text: windowText,
              detected: analysis.detectedLabels,
              score: analysis.riskScore,
            )
            .then((explanation) {
              if (_active && explanation.isNotEmpty) {
                _onExplanation?.call(explanation);
              }
            })
            .catchError((_) {});
      }
    } finally {
      _transcribing = false;
    }
  }

  Future<void> stop() async {
    _active = false;
    _textWindow.clear();
    await _capture.stop();
  }

  void dispose() {
    _active = false;
    _capture.stop();
    _nlu.dispose();
  }
}
