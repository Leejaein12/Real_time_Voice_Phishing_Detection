import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/analysis_result.dart';
import 'phishing_detector.dart';

class SttService {
  final SpeechToText _speech = SpeechToText();
  final PhishingDetector _detector = PhishingDetector();

  Function(AnalysisResult)? _onResult;
  bool _active = false;
  final List<String> _textWindow = [];

  Future<bool> start(Function(AnalysisResult) onResult) async {
    _onResult = onResult;
    _active = true;

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint('[STT] status: $status');
        if (_active && (status == 'done' || status == 'notListening')) {
          Future.delayed(const Duration(milliseconds: 300), _listen);
        }
      },
      onError: (error) {
        debugPrint('[STT] error: ${error.errorMsg}');
        if (_active) {
          Future.delayed(const Duration(seconds: 1), _listen);
        }
      },
    );

    if (!available) {
      debugPrint('[STT] speech recognition not available');
      return false;
    }

    await _listen();
    return true;
  }

  Future<void> _listen() async {
    if (!_active || _speech.isListening) return;

    await _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords;
        if (text.isEmpty) return;

        if (result.finalResult) {
          _textWindow.add(text);
          if (_textWindow.length > 10) _textWindow.removeAt(0);
        }

        final windowText = [..._textWindow, text].join(' ');
        final analysis = _detector.analyze(text, windowText);
        _onResult?.call(analysis);
      },
      localeId: 'ko_KR',
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  Future<void> stop() async {
    _active = false;
    _textWindow.clear();
    await _speech.stop();
  }

  void dispose() {
    _active = false;
    _speech.cancel();
  }
}
