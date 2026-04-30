import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// KoELECTRA 기반 보이스피싱 탐지 서비스
/// 1단계: 슬라이딩 윈도우 키워드 필터 (<10ms)
/// 2단계: TFLite 추론 (~80ms), 1단계 통과(21점 이상)시에만 실행
class PhishingAnalyzerService {
  PhishingAnalyzerService._();
  static final instance = PhishingAnalyzerService._();

  static const _maxLength = 128;
  static const _filterThreshold = 21;

  // 특수 토큰 ID
  static const _clsId = 2;
  static const _sepId = 3;
  static const _padId = 0;
  static const _unkId = 1;

  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  bool get isReady => _interpreter != null && _vocab != null;

  // ── 초기화 ──────────────────────────────────────────────────
  Future<void> initialize() async {
    await Future.wait([_loadVocab(), _loadModel()]);
  }

  Future<void> _loadVocab() async {
    final raw = await rootBundle.loadString('assets/vocab.txt');
    final lines = raw.split('\n');
    _vocab = {};
    for (var i = 0; i < lines.length; i++) {
      final word = lines[i].trim();
      if (word.isNotEmpty) _vocab![word] = i;
    }
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/model_float16.tflite');
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _vocab = null;
  }

  // ── 분석 진입점 ────────────────────────────────────────────
  /// [text]: 누적된 전체 통화 텍스트
  PhishingResult analyze(String text) {
    if (text.trim().isEmpty) return PhishingResult.safe();

    final keywordScore = _keywordFilter(text);
    if (keywordScore < _filterThreshold) {
      return PhishingResult.safe(keywordScore: keywordScore);
    }

    if (!isReady) {
      return PhishingResult(
        keywordScore: keywordScore,
        probs: [0, 0, 0],
        triggered: false,
      );
    }

    final probs = _runInference(text);
    return PhishingResult(
      keywordScore: keywordScore,
      probs: probs,
      triggered: true,
    );
  }

  // ── 1단계: 키워드 필터 ─────────────────────────────────────
  static const _keywords = <String, int>{
    // 기관사칭
    '검찰': 15, '검사': 15, '수사관': 15, '지검': 15, '경찰청': 15,
    '수사과': 15, '사무관': 15, '조사관': 15, '수사팀': 15,
    '공문': 15, '사건조회': 15, '금융감독원': 15, '금감원': 15,
    // 금전요구
    '계좌이체': 15, '안전계좌': 15, '공탁금': 15, '송금': 15,
    '현금': 15, '입금': 15, '이체': 15,
    // 개인정보
    '주민번호': 15, 'OTP': 15, '카드번호': 15, '인증번호': 15,
    '실명인증': 15, '실명확인': 15, '본인확인': 15, '비밀번호': 15,
    // 기술적 위협
    '팀뷰어': 15, '원격제어': 15, '악성코드': 15, '주소창': 15, '인터넷주소': 15,
    // 심리적 압박
    '구속영장': 15, '범죄연루': 15, '소환장': 15,
  };

  int _keywordFilter(String text) {
    var score = 0;
    _keywords.forEach((kw, pts) {
      if (text.contains(kw)) score += pts;
    });
    // URL 패턴 감지 (30점)
    if (text.contains('www')) score += 30;
    if (RegExp(r'[a-zA-Z]+\d+[a-zA-Z]*\.[a-zA-Z]{2,}').hasMatch(text)) score += 30;
    return score;
  }

  // ── 2단계: WordPiece 토크나이저 ───────────────────────────
  List<int> _tokenize(String text) {
    final vocab = _vocab!;
    final tokens = <int>[];

    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      tokens.addAll(_wordPiece(word, vocab));
      if (tokens.length >= _maxLength - 2) break;
    }

    final truncated = tokens.take(_maxLength - 2).toList();
    final inputIds = [_clsId, ...truncated, _sepId];
    while (inputIds.length < _maxLength) inputIds.add(_padId);

    return inputIds;
  }

  List<int> _wordPiece(String word, Map<String, int> vocab) {
    if (vocab.containsKey(word)) return [vocab[word]!];

    final subTokens = <int>[];
    var start = 0;
    while (start < word.length) {
      var end = word.length;
      int? curId;
      while (start < end) {
        final substr = (start == 0 ? '' : '##') + word.substring(start, end);
        if (vocab.containsKey(substr)) {
          curId = vocab[substr];
          break;
        }
        end--;
      }
      if (curId == null) return [_unkId];
      subTokens.add(curId);
      start = end;
    }
    return subTokens;
  }

  // ── 3단계: TFLite 추론 ────────────────────────────────────
  List<double> _runInference(String text) {
    final inputIds = _tokenize(text);
    final attentionMask = inputIds.map((id) => id != _padId ? 1 : 0).toList();
    final tokenTypeIds = List.filled(_maxLength, 0);

    final inputIdsT = [inputIds];
    final maskT = [attentionMask];
    final typeIdsT = [tokenTypeIds];

    final output = [List.filled(3, 0.0)];

    _interpreter!.runForMultipleInputs(
      [inputIdsT, maskT, typeIdsT],
      {0: output},
    );

    // Sigmoid
    return output[0].map((logit) => 1.0 / (1.0 + math.exp(-logit))).toList();
  }
}

// ── 결과 모델 ──────────────────────────────────────────────
class PhishingResult {
  final int keywordScore;
  final List<double> probs; // [기관사칭, 금전요구, 개인정보]
  final bool triggered;

  static const _labels = ['기관사칭', '금전요구', '개인정보'];
  static const _probThreshold = 0.5;

  PhishingResult({
    required this.keywordScore,
    required this.probs,
    required this.triggered,
  });

  factory PhishingResult.safe({int keywordScore = 0}) =>
      PhishingResult(keywordScore: keywordScore, probs: [0, 0, 0], triggered: false);

  List<String> get detectedLabels => [
    for (var i = 0; i < probs.length; i++)
      if (probs[i] >= _probThreshold) _labels[i],
  ];

  double get maxProb =>
      probs.isEmpty ? 0 : probs.reduce((a, b) => a > b ? a : b);

  int get riskPercent {
    if (!triggered) return (keywordScore / 3).clamp(0, 30).toInt();
    return (maxProb * 100).toInt();
  }

  int get warningLevel {
    final r = riskPercent;
    if (r >= 61) return 3;
    if (r >= 31) return 2;
    if (r >= 11) return 1;
    return 0;
  }
}
