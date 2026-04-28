import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/analysis_result.dart';

class NluService {
  Interpreter? _interpreter;
  Map<String, int>? _vocab;

  static const _maxLen = 128;
  static const _clsId = 2;
  static const _sepId = 3;
  static const _padId = 0;
  static const _unkId = 1;
  static const _threshold = 0.5;
  static const _labels = ['기관사칭', '금전요구', '개인정보'];

  Future<void> init() async {
    final modelData = await rootBundle.load('assets/model.tflite');
    _interpreter = Interpreter.fromBuffer(modelData.buffer.asUint8List());
    _interpreter!.resizeInputTensor(0, [1, _maxLen]);
    _interpreter!.resizeInputTensor(1, [1, _maxLen]);
    _interpreter!.resizeInputTensor(2, [1, _maxLen]);
    _interpreter!.allocateTensors();

    final tokenizerJson = await rootBundle.loadString('assets/tokenizer.json');
    final tokenizer = json.decode(tokenizerJson) as Map<String, dynamic>;
    final rawVocab = tokenizer['model']['vocab'] as Map<String, dynamic>;
    _vocab = rawVocab.map((k, v) => MapEntry(k, v as int));
  }

  List<int> _tokenize(String text) {
    final vocab = _vocab!;
    final tokens = <int>[_clsId];

    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      var remaining = word;
      var isFirst = true;
      while (remaining.isNotEmpty) {
        int bestLen = 0;
        for (int len = remaining.length; len > 0; len--) {
          final sub = isFirst ? remaining.substring(0, len) : '##${remaining.substring(0, len)}';
          if (vocab.containsKey(sub)) {
            bestLen = len;
            break;
          }
        }
        if (bestLen == 0) {
          tokens.add(_unkId);
          break;
        }
        final sub = isFirst ? remaining.substring(0, bestLen) : '##${remaining.substring(0, bestLen)}';
        tokens.add(vocab[sub]!);
        remaining = remaining.substring(bestLen);
        isFirst = false;
      }
      if (tokens.length >= _maxLen - 1) break;
    }

    tokens.add(_sepId);
    while (tokens.length < _maxLen) { tokens.add(_padId); }
    return tokens.sublist(0, _maxLen);
  }

  AnalysisResult analyze(String text) {
    if (_interpreter == null || _vocab == null || text.isEmpty) {
      return AnalysisResult(text: text, riskScore: 0, warningLevel: 0, explanation: '정상적인 통화로 보입니다.');
    }

    final ids = _tokenize(text);
    final mask = ids.map((id) => id != _padId ? 1 : 0).toList();
    final typeIds = List.filled(_maxLen, 0);

    // int64 입력 (모델이 int64 요구)
    final idsInt64 = Int64List.fromList(ids);
    final maskInt64 = Int64List.fromList(mask);
    final typeIdsInt64 = Int64List.fromList(typeIds);

    // float32 출력 (3개 값 × 4바이트)
    final outBuffer = Float32List(3);

    try {
      final inputs = <Object>[[idsInt64], [maskInt64], [typeIdsInt64]];
      final outputs = <int, Object>{0: outBuffer};
      _interpreter!.runForMultipleInputs(inputs, outputs);
    } catch (e) {
      debugPrint('[NLU] 오류: $e');
      return AnalysisResult(text: text, riskScore: 0, warningLevel: 0, explanation: '정상적인 통화로 보입니다.');
    }

    final probs = List.generate(3, (i) {
      return 1.0 / (1.0 + math.exp(-outBuffer[i]));
    });

    final detected = <String>[];
    for (int i = 0; i < _labels.length; i++) {
      if (probs[i] >= _threshold) detected.add(_labels[i]);
    }

    final riskScore = (probs.reduce((a, b) => a > b ? a : b) * 100).round().clamp(0, 100);
    final level = riskScore >= 75 ? 3 : riskScore >= 50 ? 2 : riskScore >= 25 ? 1 : 0;
    final explanation = switch (level) {
      3 => '즉시 통화를 끊으세요. ${detected.join(', ')} 위험이 감지됐습니다.',
      2 => '의심스러운 패턴이 감지됐습니다. 주의하세요.',
      1 => '일부 주의 패턴이 감지됐습니다.',
      _ => '정상적인 통화로 보입니다.',
    };

    debugPrint('[NLU] probs=$probs score=$riskScore level=$level detected=$detected');
    return AnalysisResult(text: text, riskScore: riskScore, warningLevel: level, explanation: explanation, detectedLabels: detected);
  }

  void dispose() => _interpreter?.close();
}
