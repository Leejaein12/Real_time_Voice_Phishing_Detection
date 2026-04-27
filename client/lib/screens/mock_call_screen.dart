import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

// ── 더미 시나리오 (실제 LLM 분석 결과 포맷 그대로) ─────────────────────────
class _Scenario {
  final int level;
  final int score;
  final String text;
  final String? reason;
  const _Scenario({required this.level, required this.score, required this.text, this.reason});
}

const _scenarios = [
  _Scenario(level: 0, score: 5,  text: '네, 알겠습니다. 오늘 안에 처리해 드리겠습니다.',
      reason: null),
  _Scenario(level: 0, score: 11, text: '죄송한데 지금 좀 바빠서요, 나중에 연락드릴게요.',
      reason: null),
  _Scenario(level: 1, score: 43, text: '지금 당장 계좌번호를 알려주시면 처리해 드리겠습니다.',
      reason: '금융 정보 요청 패턴 감지 — 실제 기관은 전화로 계좌번호를 요구하지 않습니다.'),
  _Scenario(level: 1, score: 51, text: '본인 확인을 위해 주민등록번호 뒷자리를 말씀해 주세요.',
      reason: '개인정보 요구 패턴 — 정상 기관은 전화 인증 시 주민번호를 요청하지 않습니다.'),
  _Scenario(level: 2, score: 74, text: '검찰청입니다. 고객님 계좌가 범죄에 이용되고 있습니다.',
      reason: '수사기관 사칭 패턴 감지 — "검찰·경찰이 전화로 수사 협조 요청"은 전형적인 보이스피싱 수법입니다.'),
  _Scenario(level: 2, score: 81, text: '지금 바로 안전 계좌로 이체하지 않으면 자산이 동결됩니다.',
      reason: '"안전 계좌 이체" 요구는 보이스피싱의 핵심 수법입니다. 즉시 전화를 끊으세요.'),
  _Scenario(level: 3, score: 96, text: '지금 즉시 송금하지 않으면 영장을 발부하겠습니다.',
      reason: '협박 + 송금 강요 패턴 감지. 딥보이스 합성 목소리 의심 (신뢰도 88%). 즉시 전화를 끊고 112에 신고하세요.'),
  _Scenario(level: 3, score: 99, text: '가족이 사고가 났습니다. 합의금을 지금 바로 보내주세요.',
      reason: '가족 납치·사고 빙자 긴급 송금 요구. 딥보이스 합성 목소리 탐지 (신뢰도 93%). 즉시 가족에게 직접 연락하세요.'),
];

const _levelBorderColors = [
  Colors.transparent,
  Color(0xFFEAB308),
  Color(0xFFEA580C),
  Color(0xFFDC2626),
];
const _levelColors = [
  Color(0xFF16A34A),
  Color(0xFFEAB308),
  Color(0xFFEA580C),
  Color(0xFFDC2626),
];
const _levelLabels = ['안전', '주의', '경고', '위험'];

class MockCallScreen extends StatefulWidget {
  const MockCallScreen({super.key});
  @override
  State<MockCallScreen> createState() => _MockCallScreenState();
}

class _MockCallScreenState extends State<MockCallScreen> with TickerProviderStateMixin {
  int _seconds = 0;
  Timer? _callTimer;
  Timer? _analysisTimer;
  _Scenario _current = _scenarios[0];
  late AnimationController _borderPulse;

  @override
  void initState() {
    super.initState();
    _borderPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });

    // 첫 분석은 2초 후, 이후 4초마다
    Future.delayed(const Duration(seconds: 2), _runAnalysis);
    _analysisTimer = Timer.periodic(const Duration(seconds: 4), (_) => _runAnalysis());
  }

  void _runAnalysis() {
    if (!mounted) return;
    final next = _scenarios[Random().nextInt(_scenarios.length)];
    setState(() => _current = next);
    if (Platform.isAndroid) {
      FlutterOverlayWindow.shareData({
        'warning_level': next.level,
        'text': next.text,
      });
    }
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _analysisTimer?.cancel();
    _borderPulse.dispose();
    super.dispose();
  }

  String get _duration {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _endCall() async {
    try {
      if (Platform.isAndroid && await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final level = _current.level;
    final borderColor = _levelBorderColors[level];
    final levelColor = _levelColors[level];

    return AnimatedBuilder(
      animation: _borderPulse,
      builder: (_, w) {
        final pulse = level >= 3 ? _borderPulse.value : 1.0;
        final borderWidth = level == 0 ? 0.0 : (3.0 + pulse * 2);

        return Scaffold(
          backgroundColor: Colors.black,
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              border: level == 0
                  ? null
                  : Border.all(color: borderColor.withValues(alpha: 0.85), width: borderWidth),
              boxShadow: level >= 2
                  ? [BoxShadow(color: borderColor.withValues(alpha: 0.3 * pulse), blurRadius: 24, spreadRadius: 4)]
                  : null,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: level >= 2
                          ? [const Color(0xFF1C0A0A), const Color(0xFF2C1010), const Color(0xFF1A0808)]
                          : [const Color(0xFF1C1C2E), const Color(0xFF2C2C3E), const Color(0xFF1A1A2E)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      // ── 상단 바: 뒤로가기 + 점수 뱃지 ──────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _endCall,
                              child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 28),
                            ),
                            const Spacer(),
                            // Score badge
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: levelColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: levelColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.analytics_rounded, color: levelColor, size: 13),
                                const SizedBox(width: 5),
                                Text(
                                  '위험도 ${_current.score}',
                                  style: TextStyle(color: levelColor, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── 발신자 정보 ─────────────────────────────────────
                      Container(
                        width: 88, height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 2),
                          ],
                        ),
                        child: const Center(
                          child: Text('E', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w300)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('EST', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w300, letterSpacing: 1.5)),
                      const SizedBox(height: 4),
                      Text(_duration, style: const TextStyle(color: Colors.white54, fontSize: 16)),
                      const SizedBox(height: 8),

                      // Vaia 분석 중 배지
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text('Vaia 분석 중', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontWeight: FontWeight.w500)),
                        ]),
                      ),

                      const SizedBox(height: 12),

                      // ── 분석 결과 카드 ──────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: _ResultCard(key: ValueKey(_current.score), scenario: _current),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── iOS 버튼 그리드 ─────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 44),
                        child: _IOSButtonGrid(),
                      ),

                      const SizedBox(height: 16),

                      // ── 전화 종료 버튼 ───────────────────────────────────
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          width: 68, height: 68,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFFFF3B30).withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 4))],
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                        ),
                      ),

                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 분석 결과 카드 ──────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  final _Scenario scenario;
  const _ResultCard({super.key, required this.scenario});

  @override
  Widget build(BuildContext context) {
    final level = scenario.level;
    final color = _levelColors[level];
    final label = _levelLabels[level];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: level == 0 ? 0.2 : 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          Text('STT 분석', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        Text(
          '"${scenario.text}"',
          style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (scenario.reason != null) ...[
          const SizedBox(height: 10),
          Container(height: 1, color: color.withValues(alpha: 0.2)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.smart_toy_rounded, color: color, size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                scenario.reason!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 11, height: 1.5),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ── iOS 스타일 버튼 그리드 ───────────────────────────────────────────────────
class _IOSButtonGrid extends StatefulWidget {
  @override
  State<_IOSButtonGrid> createState() => _IOSButtonGridState();
}

class _IOSButtonGridState extends State<_IOSButtonGrid> {
  bool _muted = false;
  bool _speaker = false;
  bool _keypad = false;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.0,
      children: [
        _Btn(icon: Icons.mic_off_rounded, label: '음소거', active: _muted, onTap: () => setState(() => _muted = !_muted)),
        _Btn(icon: Icons.dialpad_rounded, label: '키패드', active: _keypad, onTap: () => setState(() => _keypad = !_keypad)),
        _Btn(icon: Icons.volume_up_rounded, label: '스피커', active: _speaker, onTap: () => setState(() => _speaker = !_speaker)),
        _Btn(icon: Icons.add_rounded, label: '통화추가', onTap: () {}),
        _Btn(icon: Icons.videocam_rounded, label: 'FaceTime', onTap: () {}),
        _Btn(icon: Icons.person_rounded, label: '연락처', onTap: () {}),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: active ? Colors.black : Colors.white, size: 24),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
      ]),
    );
  }
}
