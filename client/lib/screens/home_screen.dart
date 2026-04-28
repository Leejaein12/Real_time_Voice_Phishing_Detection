import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/call_record.dart';
import 'mock_call_screen.dart';

const _kPrimary = Color(0xFF3B82F6);
const _kPrimaryLight = Color(0xFF60A5FA);
const _kText = Color(0xFF111827);
const _kTextSub = Color(0xFF6B7280);
const _kTextHint = Color(0xFF9CA3AF);

const _levelColors = [
  Color(0xFF16A34A),
  Color(0xFFD97706),
  Color(0xFFEA580C),
  Color(0xFFDC2626),
];
const _levelIcons = [
  Icons.check_circle_rounded,
  Icons.warning_amber_rounded,
  Icons.warning_amber_rounded,
  Icons.dangerous_rounded,
];
const _levelLabels = ['안전', '주의', '경고', '위험'];

class HomeScreen extends StatefulWidget {
  final List<CallRecord> records;
  final bool isProtectionOn;
  final VoidCallback onToggle;
  const HomeScreen({super.key, required this.records, required this.isProtectionOn, required this.onToggle});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _chartCtrl;
  late List<Animation<double>> _sectionAnims;

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  int get _detected => widget.records.where((r) => _isToday(r.timestamp) && r.warningLevel >= 1).length;
  int get _warned => widget.records.where((r) => _isToday(r.timestamp) && r.warningLevel >= 2).length;
  int get _safe => widget.records.where((r) => _isToday(r.timestamp) && r.warningLevel == 0).length;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _chartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _sectionAnims = [
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.15, 0.65, curve: Curves.easeOut)),
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.3, 0.8, curve: Curves.easeOut)),
      CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.45, 1.0, curve: Curves.easeOut)),
    ];
    _entryCtrl.forward();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _chartCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _chartCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_kPrimary, _kPrimaryLight]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.shield, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Vaia', style: TextStyle(color: _kText, fontWeight: FontWeight.bold, fontSize: 20)),
                const Text('실시간 보이스피싱 탐지', style: TextStyle(color: _kTextSub, fontSize: 11)),
              ]),
            ),
            Stack(alignment: Alignment.center, children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: _kTextSub),
                onPressed: () {},
              ),
              if (_detected > 0)
                Positioned(
                  right: 10, top: 10,
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                ),
            ]),
          ]),
          const SizedBox(height: 20),
          _FadeSlide(
            animation: _sectionAnims[0],
            child: _StatusCard(isOn: widget.isProtectionOn, onToggle: widget.onToggle, totalCalls: widget.records.length, pulseCtrl: _pulseCtrl),
          ),
          const SizedBox(height: 14),
          _FadeSlide(
            animation: _sectionAnims[1],
            child: _StatsRow(detected: _detected, warned: _warned, safe: _safe),
          ),
          const SizedBox(height: 14),
          _FadeSlide(
            animation: _sectionAnims[2],
            child: _WeeklyChart(records: widget.records, chartCtrl: _chartCtrl),
          ),
          const SizedBox(height: 14),
          _FadeSlide(
            animation: _sectionAnims[3],
            child: _RecentHistory(records: widget.records.reversed.take(5).toList()),
          ),
          if (!Platform.isAndroid && !Platform.isIOS) ...[
            const SizedBox(height: 14),
            _CallTestButton(),
          ],
        ],
      ),
    );
  }
}

class _CallTestButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MockCallScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: const Color(0xFF16A34A).withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.call_rounded, color: Colors.white, size: 20),
          SizedBox(width: 10),
          Text('전화 연결 테스트', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _FadeSlide({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 18 * (1 - animation.value)), child: child),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const _GlassCard({required this.child, required this.padding, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggle;
  final int totalCalls;
  final AnimationController pulseCtrl;
  const _StatusCard({required this.isOn, required this.onToggle, required this.totalCalls, required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOn
              ? [const Color(0xFF1E40AF), const Color(0xFF1E5FD8), const Color(0xFF3B82F6)]
              : [const Color(0xFF374151), const Color(0xFF4B5563)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: isOn
            ? [BoxShadow(color: const Color(0xFF3B82F6).withValues(alpha: 0.4), blurRadius: 28, offset: const Offset(0, 8))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AnimatedBuilder(
            animation: pulseCtrl,
            builder: (_, _) => SizedBox(
              width: 56, height: 56,
              child: Stack(alignment: Alignment.center, children: [
                if (isOn)
                  Container(
                    width: 44 + 10 * pulseCtrl.value,
                    height: 44 + 10 * pulseCtrl.value,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1 * (1 - pulseCtrl.value)),
                      shape: BoxShape.circle,
                    ),
                  ),
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.shield, color: Colors.white, size: 24),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('보호 상태', style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(isOn ? '보호 중' : '대기 중',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.2)),
            ]),
          ),
          Switch(
            value: isOn,
            onChanged: (_) => onToggle(),
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF4ADE80),
            inactiveThumbColor: Colors.white60,
            inactiveTrackColor: Colors.white24,
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            AnimatedBuilder(
              animation: pulseCtrl,
              builder: (_, _) => Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: isOn ? const Color(0xFF4ADE80) : Colors.white38,
                  shape: BoxShape.circle,
                  boxShadow: isOn
                      ? [BoxShadow(color: const Color(0xFF4ADE80).withValues(alpha: 0.5 * pulseCtrl.value), blurRadius: 6, spreadRadius: 2)]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isOn ? 'AI 분석 엔진 활성화 · 총 $totalCalls건 분석' : 'AI 분석 엔진 대기 중',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int detected, warned, safe;
  const _StatsRow({required this.detected, required this.warned, required this.safe});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _StatCard(icon: Icons.gps_fixed_rounded, iconColor: _kPrimary, bgColor: const Color(0xFFEFF6FF), count: detected, label: '오늘 탐지'),
      const SizedBox(width: 10),
      _StatCard(icon: Icons.warning_rounded, iconColor: const Color(0xFFEA580C), bgColor: const Color(0xFFFFF7ED), count: warned, label: '경고 발생'),
      const SizedBox(width: 10),
      _StatCard(icon: Icons.check_circle_rounded, iconColor: const Color(0xFF16A34A), bgColor: const Color(0xFFF0FDF4), count: safe, label: '안전 통화'),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final int count;
  final String label;
  const _StatCard({required this.icon, required this.iconColor, required this.bgColor, required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: count),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            builder: (_, val, _) => Text('$val건', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kText)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: _kTextSub, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final List<CallRecord> records;
  final AnimationController chartCtrl;
  const _WeeklyChart({required this.records, required this.chartCtrl});

  @override
  Widget build(BuildContext context) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final counts = List.filled(7, 0);
    final now = DateTime.now();
    final today = now.weekday - 1;
    final weekStart = now.subtract(Duration(days: today));

    for (final r in records) {
      final isThisWeek = !r.timestamp.isBefore(DateTime(weekStart.year, weekStart.month, weekStart.day));
      if (isThisWeek && r.warningLevel >= 1) counts[r.timestamp.weekday - 1]++;
    }
    final maxCount = counts.reduce((a, b) => a > b ? a : b).clamp(1, 999);

    return _GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('주간 탐지 현황', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kText)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20)),
            child: const Text('이번 주', style: TextStyle(color: _kPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: chartCtrl,
          builder: (_, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final isToday = i == today;
              final ratio = counts[i] / maxCount;
              final delay = i / 7 * 0.5;
              final progress = ((chartCtrl.value - delay) / (1 - delay)).clamp(0.0, 1.0);
              final easedProgress = Curves.easeOut.transform(progress);
              final barHeight = (60 * ratio * easedProgress + 4).clamp(4.0, 64.0);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(children: [
                    SizedBox(
                      height: 16,
                      child: counts[i] > 0 && progress > 0
                          ? Opacity(
                              opacity: easedProgress,
                              child: Text('${counts[i]}', textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 10, color: isToday ? _kPrimary : _kTextHint, fontWeight: FontWeight.bold)),
                            )
                          : null,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        gradient: isToday ? const LinearGradient(colors: [_kPrimary, _kPrimaryLight], begin: Alignment.bottomCenter, end: Alignment.topCenter) : null,
                        color: isToday ? null : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(days[i], style: TextStyle(
                      fontSize: 11,
                      color: isToday ? _kPrimary : _kTextHint,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    )),
                  ]),
                ),
              );
            }),
          ),
        ),
      ]),
    );
  }
}

class _RecentHistory extends StatelessWidget {
  final List<CallRecord> records;
  const _RecentHistory({required this.records});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('최근 탐지 이력', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kText)),
          GestureDetector(
            onTap: () {},
            child: const Text('전체 보기 ›', style: TextStyle(color: _kPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      if (records.isEmpty)
        _GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Column(children: [
              const Icon(Icons.history_rounded, color: Color(0xFFD1D5DB), size: 36),
              const SizedBox(height: 8),
              const Text('탐지 이력이 없습니다', style: TextStyle(color: _kTextSub, fontSize: 13)),
            ]),
          ),
        )
      else
        ...records.asMap().entries.map((e) {
          final r = e.value;
          final isLast = e.key == records.length - 1;
          final color = _levelColors[r.warningLevel];
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: _GlassCard(
              radius: 14,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(_levelIcons[r.warningLevel], color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(r.text, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                        child: Text(_levelLabels[r.warningLevel], style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text('${r.durationString} · ${r.timestamp.month}.${r.timestamp.day}',
                        style: const TextStyle(color: _kTextHint, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1D5DB), size: 18),
              ]),
            ),
          );
        }),
    ]);
  }
}
