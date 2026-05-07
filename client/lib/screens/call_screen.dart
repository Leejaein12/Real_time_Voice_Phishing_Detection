import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../services/phishing_analyzer_service.dart';
import '../models/analysis_result.dart';

enum _Phase { ringing, active, ended }

class CallScreen extends StatefulWidget {
  /// assets/audio/ 안의 WAV 파일명 — 시뮬레이션용 재생 파일
  final String audioAsset;
  final String callerName;
  final String callerNumber;

  const CallScreen({
    super.key,
    this.audioAsset = '',
    this.callerName = '알 수 없음',
    this.callerNumber = '010-0000-0000',
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  _Phase _phase = _Phase.ringing;

  final _player = AudioPlayer();
  final _speech = SpeechToText();
  final _analyzer = PhishingAnalyzerService.instance;

  // STT 결과
  String _fullText = '';       // 확정된 누적 텍스트
  String _partialText = '';    // 현재 인식 중 텍스트 (회색 이탤릭)
  int _warningLevel = 0;
  int _riskPercent = 0;
  int _peakRiskPercent = 0;
  final List<String> _detectedLabels = [];
  bool _hangupWarningShown = false;
  String? _errorMsg;
  String? _audioStatus;
  bool _callActive = false;

  // 타이머
  Duration _elapsed = Duration.zero;
  Timer? _callTimer;

  StreamSubscription<PlaybackEvent>? _playbackSub;

  // 애니메이션
  late AnimationController _ringCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _initAll();
  }

  @override
  void dispose() {
    _callActive = false;
    _callTimer?.cancel();
    _speech.cancel();
    _playbackSub?.cancel();
    _player.dispose();
    _ringCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _initAll() async {
    // SpeechRecognizer 초기화 (마이크 권한 요청 포함)
    final available = await _speech.initialize(
      onError: (e) {
        debugPrint('[STT] 오류: ${e.errorMsg}');
        if (mounted) setState(() {});
      },
      onStatus: _onSpeechStatus,
    );
    if (!available && mounted) {
      setState(() => _errorMsg = '마이크 권한이 필요합니다');
    }

    // TFLite 분석 모델 초기화 (백그라운드)
    if (!_analyzer.isReady) {
      _analyzer.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((e) {
        debugPrint('[Analyzer] 초기화 오류: $e');
        if (mounted) setState(() {});
      });
    }

    if (mounted) setState(() {});
  }

  // ── 전화 받기 ──────────────────────────────────────────────
  Future<void> _answerCall() async {
    setState(() {
      _phase = _Phase.active;
      _callActive = true;
    });
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
    if (widget.audioAsset.isNotEmpty) unawaited(_startPlayback());
    unawaited(_startListening());
  }

  // 시뮬레이션용 오디오 재생 (실기기에서 스피커 → 마이크로 픽업)
  Future<void> _startPlayback() async {
    try {
      await _player.setAsset('assets/audio/${widget.audioAsset}');
      _playbackSub = _player.playbackEventStream.listen(
        (_) {},
        onError: (Object e, StackTrace _) {
          if (mounted) setState(() => _audioStatus = '음성파일 없음');
        },
      );
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _audioStatus = '음성파일 없음');
    }
  }

  // ── SpeechRecognizer STT ───────────────────────────────────
  Future<void> _startListening() async {
    if (!_speech.isAvailable || !mounted || !_callActive) return;
    try {
      await _speech.listen(
        onResult: _onSpeechResult,
        localeId: 'ko_KR',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[STT] listen 오류: $e');
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() => _partialText = result.recognizedWords);

    if (result.finalResult && result.recognizedWords.isNotEmpty) {
      setState(() {
        _fullText += (_fullText.isEmpty ? '' : ' ') + result.recognizedWords;
        _partialText = '';
      });
      _updateWarningLevel(_fullText);
    }
  }

  void _onSpeechStatus(String status) {
    debugPrint('[STT] 상태: $status');
    if (mounted) setState(() {});
    // listenFor(30초) 만료 후 자동 재시작으로 무한 청취
    if (status == 'done' && _callActive && mounted) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_callActive && mounted) _startListening();
      });
    }
  }

  // ── 전화 끊기 ──────────────────────────────────────────────
  Future<void> _endCall() async {
    _callActive = false;
    _callTimer?.cancel();
    await _speech.stop();
    await _player.stop();
    // 끊기 직전 인식 중이던 부분 결과도 포함
    if (_partialText.isNotEmpty) {
      _fullText += (_fullText.isEmpty ? '' : ' ') + _partialText;
      _partialText = '';
    }
    setState(() => _phase = _Phase.ended);
    if (_fullText.isNotEmpty) _updateWarningLevel(_fullText);
  }

  void _popWithResult() {
    Navigator.of(context).pop(AnalysisResult(
      text: _fullText.isEmpty ? '(인식된 텍스트 없음)' : _fullText,
      riskScore: _peakRiskPercent,
      warningLevel: _peakRiskPercent >= 61
          ? 3
          : _peakRiskPercent >= 31
              ? 2
              : _peakRiskPercent >= 11
                  ? 1
                  : 0,
      explanation: '',
      detectedLabels: _detectedLabels,
    ));
  }

  static const _hangupThreshold = 70;

  void _updateWarningLevel(String text) {
    final words = text.split(RegExp(r'\s+'));
    final window = words.length > 100
        ? words.sublist(words.length - 100).join(' ')
        : text;

    debugPrint('[UI] 분석 텍스트(${words.length}단어): "$window"');
    final result = _analyzer.analyze(window);
    debugPrint('[UI] keyword=${result.keywordScore} risk=${result.riskPercent}% triggered=${result.triggered} labels=${result.detectedLabels}');
    setState(() {
      _warningLevel = result.warningLevel;
      _riskPercent = result.riskPercent;
      if (result.riskPercent > _peakRiskPercent) _peakRiskPercent = result.riskPercent;
      for (final l in result.detectedLabels) {
        if (!_detectedLabels.contains(l)) _detectedLabels.add(l);
      }
    });

    if (result.riskPercent >= _hangupThreshold &&
        !_hangupWarningShown &&
        _phase == _Phase.active) {
      _hangupWarningShown = true;
      _showHangupWarning();
    }
  }

  void _showHangupWarning() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 28),
          SizedBox(width: 10),
          Text('보이스피싱 의심',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          '위험도 75% 이상으로 보이스피싱이 의심됩니다.\n지금 바로 전화를 끊으세요.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('계속 받기',
                style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _endCall();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('전화 끊기',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.ringing => _buildRinging(),
          _Phase.active  => _buildActive(),
          _Phase.ended   => _buildEnded(),
        },
      ),
    );
  }

  // ── 수신 화면 ──────────────────────────────────────────────
  Widget _buildRinging() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 80),
        Column(children: [
          AnimatedBuilder(
            animation: _ringCtrl,
            builder: (_, _) => Stack(alignment: Alignment.center, children: [
              Container(
                width: 120 + 30 * _ringCtrl.value,
                height: 120 + 30 * _ringCtrl.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white
                      .withValues(alpha: 0.05 * (1 - _ringCtrl.value)),
                ),
              ),
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                child:
                    const Icon(Icons.person, color: Colors.white70, size: 44),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text(widget.callerName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.callerNumber,
              style: const TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('수신 전화',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          if (!_analyzer.isReady) ...[
            const SizedBox(height: 16),
            const Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white38),
              ),
              SizedBox(width: 8),
              Text('AI 모델 초기화 중 (최초 1회, 약 15~30초)…',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ],
          if (_audioStatus != null) ...[
            const SizedBox(height: 6),
            Text(_audioStatus!,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Text(_errorMsg!,
                style:
                    const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
          ],
        ]),
        Padding(
          padding: const EdgeInsets.only(bottom: 60),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _CircleBtn(
                icon: Icons.call_end,
                color: const Color(0xFFEF4444),
                label: '거절',
                onTap: () => Navigator.of(context).pop(),
              ),
              _CircleBtn(
                icon: Icons.call,
                color: const Color(0xFF22C55E),
                label: '받기',
                onTap: _answerCall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 위험도 인디케이터 ──────────────────────────────────────
  static const _riskColors = [
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEA580C),
    Color(0xFFEF4444),
  ];
  static const _riskLabels = ['안전', '주의', '경고', '위험'];

  Widget _buildRiskIndicator() {
    final color = _riskColors[_warningLevel];
    final label = _riskLabels[_warningLevel];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (!_analyzer.isReady) ...[
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white38),
                ),
                const SizedBox(width: 6),
                const Text('AI 로딩 중',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(width: 8),
              ] else ...[
                Text('모델: ${_analyzer.modelVersion}',
                    style: const TextStyle(color: Colors.white24, fontSize: 10)),
                const SizedBox(width: 8),
              ],
              Text('$_riskPercent%',
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _riskPercent / 100,
                minHeight: 4,
                backgroundColor: Colors.white12,
                color: color,
              ),
            ),
            if (_detectedLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _detectedLabels
                    .map((l) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: color.withValues(alpha: 0.4)),
                          ),
                          child: Text(l,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 통화 중 화면 ───────────────────────────────────────────
  Widget _buildActive() {
    final mm = _elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        const SizedBox(height: 20),
        Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1)),
            child: const Icon(Icons.person, color: Colors.white70, size: 32),
          ),
          const SizedBox(height: 10),
          Text(widget.callerName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$mm:$ss',
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        _buildRiskIndicator(),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.text_fields_rounded,
                        color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    const Text('실시간 텍스트',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 12)),
                    const Spacer(),
                    if (_speech.isListening)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white38),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: _errorMsg ??
                                (_fullText.isEmpty && _partialText.isEmpty
                                    ? (_speech.isListening
                                        ? '듣는 중...'
                                        : '대기 중')
                                    : _fullText),
                            style: TextStyle(
                              color: _errorMsg != null
                                  ? const Color(0xFFEF4444)
                                  : Colors.white,
                              fontSize: 15,
                              height: 1.7,
                            ),
                          ),
                          // 인식 중인 부분 결과 — 회색 이탤릭
                          if (_partialText.isNotEmpty)
                            TextSpan(
                              text: (_fullText.isEmpty ? '' : ' ') +
                                  _partialText,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 15,
                                height: 1.7,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 40, top: 20),
          child: _CircleBtn(
            icon: Icons.call_end,
            color: const Color(0xFFEF4444),
            label: '끊기',
            size: 70,
            onTap: _endCall,
          ),
        ),
      ],
    );
  }

  // ── 통화 종료 화면 ─────────────────────────────────────────
  Widget _buildEnded() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 28),
              onPressed: _popWithResult,
            ),
            const Spacer(),
            const Text('통화 분석 결과',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const Spacer(),
            const SizedBox(width: 48),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('인식된 텍스트',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12)),
                      const SizedBox(height: 10),
                      Text(
                        _fullText.isEmpty ? '(인식된 텍스트 없음)' : _fullText,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _popWithResult,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('결과 저장',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;
  const _CircleBtn({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: Colors.white, size: size * 0.45),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
