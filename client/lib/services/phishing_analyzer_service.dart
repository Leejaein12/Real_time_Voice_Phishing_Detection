import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// KoELECTRA 기반 보이스피싱 탐지 서비스
/// 1단계: 슬라이딩 윈도우 키워드 필터 (<10ms)
/// 2단계: TFLite 추론 (~80ms), 1단계 통과(21점 이상)시에만 실행
class PhishingAnalyzerService {
  PhishingAnalyzerService._();
  static final instance = PhishingAnalyzerService._();

  static const _maxLength = 128;
  static const _filterThreshold = 15;

  // 특수 토큰 ID
  static const _clsId = 2;
  static const _sepId = 3;
  static const _padId = 0;
  static const _unkId = 1;

  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  String _modelVersion = '없음';

  // --dart-define으로 빌드 시 주입. 기본값: dynamic range quant
  static const _modelFile = String.fromEnvironment(
    'MODEL_FILE',
    defaultValue: 'model_int8_no_erf.tflite',
  );
  static const _modelLabel = String.fromEnvironment(
    'MODEL_LABEL',
    defaultValue: 'int8',
  );

  bool get isReady => _interpreter != null && _vocab != null;
  String get modelVersion => _modelVersion;

  // ── 초기화 ──────────────────────────────────────────────────
  Future<void> initialize() async {
    debugPrint('[Analyzer] initialize() 시작');
    await Future.wait([_loadVocab(), _loadModel()]);
    debugPrint('[Analyzer] initialize() 완료');
  }

  Future<void> _loadVocab() async {
    final raw = await rootBundle.loadString('assets/vocab.txt');
    final lines = raw.split('\n');
    _vocab = {};
    for (var i = 0; i < lines.length; i++) {
      final word = lines[i].trim();
      if (word.isNotEmpty) _vocab![word] = i;
    }
    debugPrint('[Analyzer] vocab 로드 완료: ${_vocab!.length}개');
  }

  static InterpreterOptions get _cpuOptions =>
      InterpreterOptions()..threads = 2;

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/$_modelFile',
        options: _cpuOptions,
      );
      _interpreter!.allocateTensors();
      _modelVersion = _modelLabel;
      debugPrint('[Analyzer] 모델 로드 성공 ($_modelLabel)');
      // 텐서 정보 출력 (타입/형태 확인용)
      for (var i = 0; i < _interpreter!.getInputTensors().length; i++) {
        final t = _interpreter!.getInputTensors()[i];
        debugPrint('[Analyzer] 입력텐서[$i]: ${t.name} shape=${t.shape} type=${t.type}');
      }
      for (var i = 0; i < _interpreter!.getOutputTensors().length; i++) {
        final t = _interpreter!.getOutputTensors()[i];
        debugPrint('[Analyzer] 출력텐서[$i]: ${t.name} shape=${t.shape} type=${t.type}');
      }
    } catch (e) {
      _modelVersion = '없음 (키워드 필터만)';
      debugPrint('[Analyzer] 모델 로드 실패 ($_modelLabel): $e');
    }
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
    debugPrint('[Analyzer] keywordScore=$keywordScore, isReady=$isReady');

    if (keywordScore < _filterThreshold) {
      debugPrint('[Analyzer] 필터 미통과 → safe');
      return PhishingResult.safe(keywordScore: keywordScore);
    }

    if (!isReady) {
      debugPrint('[Analyzer] 필터 통과($keywordScore) but 모델 미준비 → triggered=false');
      return PhishingResult(
        keywordScore: keywordScore,
        probs: [0, 0, 0],
        triggered: false,
      );
    }

    try {
      final probs = _runInference(text);
      debugPrint('[Analyzer] 추론 완료 → probs=${probs.map((p) => p.toStringAsFixed(2)).toList()}');
      return PhishingResult(
        keywordScore: keywordScore,
        probs: probs,
        triggered: true,
      );
    } catch (e, st) {
      debugPrint('[Analyzer] 추론 오류: $e');
      debugPrint('[Analyzer] 스택트레이스: $st');
      return PhishingResult(keywordScore: keywordScore, probs: [0, 0, 0], triggered: false);
    }
  }

  // ── 1단계: 키워드 필터 ─────────────────────────────────────
  static const _keywords = <String, int>{
    // 기관사칭
    '검찰': 15, '검사': 15, '수사관': 15, '지검': 15, '경찰청': 15,
    '수사과': 15, '사무관': 15, '조사관': 15, '수사팀': 15,
    '공문': 15, '사건조회': 15, '금융감독원': 15, '금감원': 15,
    // 금전요구
    '계좌이체': 15, '안전계좌': 15, '공탁금': 15, '송금': 15,
    '현금': 15, '입금': 15, '이체': 15, '계좌': 10,
    // 개인정보
    '주민번호': 15, 'OTP': 15, '카드번호': 15, '인증번호': 15,
    '실명인증': 15, '실명확인': 15, '본인확인': 15, '비밀번호': 15,
    '비번': 10, '패스워드': 10,
    // 기관 관련 (STT 오인식 대응)
    '금융권': 10, '공공기관': 10, '수사': 10,
    // 기술적 위협
    '팀뷰어': 15, '원격제어': 15, '악성코드': 15, '주소창': 15, '인터넷주소': 15,
    // 심리적 압박
    '구속영장': 15, '범죄연루': 15, '소환장': 15,
  };

  int _keywordFilter(String text) {
    // STT가 복합어에 공백을 삽입하는 경우 대비 (예: "안전 계좌" → "안전계좌")
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    var score = 0;
    _keywords.forEach((kw, pts) {
      if (text.contains(kw) || normalized.contains(kw)) score += pts;
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
    while (inputIds.length < _maxLength) { inputIds.add(_padId); }

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

    // List<Int64List>로 감싸면 내부에서 int32(4바이트)로 처리돼 크기 불일치 발생
    // → buffer.asUint8List()로 raw 바이트(128×8=1024B)를 직접 전달
    final output = [List.filled(3, 0.0)];

    // 텐서 순서: [0]=attention_mask, [1]=input_ids, [2]=token_type_ids
    _interpreter!.runForMultipleInputs(
      [
        Int64List.fromList(attentionMask).buffer.asUint8List(),
        Int64List.fromList(inputIds).buffer.asUint8List(),
        Int64List.fromList(tokenTypeIds).buffer.asUint8List(),
      ],
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
