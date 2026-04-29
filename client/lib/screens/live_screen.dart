import 'package:flutter/material.dart';
import '../models/analysis_result.dart';

class LiveScreen extends StatelessWidget {
  final AnalysisResult? result;
  final bool isProtectionOn;
  final void Function(AnalysisResult)? onResult;

  const LiveScreen({
    super.key,
    required this.result,
    required this.isProtectionOn,
    this.onResult,
  });

  static const _levelColors = [
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFFEA580C),
    Color(0xFFDC2626),
  ];
  static const _levelBgColors = [
    Color(0xFFF0FDF4),
    Color(0xFFFFFBEB),
    Color(0xFFFFF7ED),
    Color(0xFFFFF1F2),
  ];
  static const _levelLabels = ['안전', '주의', '경고', '위험'];
  static const _levelIcons = [
    Icons.check_circle_rounded,
    Icons.warning_amber_rounded,
    Icons.warning_amber_rounded,
    Icons.dangerous_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('통화 분석', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 20),
          if (!isProtectionOn)
            _buildOffCard()
          else if (result == null)
            _buildWaitingCard()
          else
            _buildResultCard(result!),
        ],
      ),
    );
  }

  Widget _buildOffCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(children: [
        Icon(Icons.shield_outlined, size: 48, color: Color(0xFF94A3B8)),
        SizedBox(height: 12),
        Text('보호가 꺼져 있습니다', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
        SizedBox(height: 6),
        Text('홈 화면에서 보호를 켜주세요', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
      ]),
    );
  }

  Widget _buildWaitingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(children: [
        Icon(Icons.phone_in_talk_rounded, size: 48, color: Color(0xFF3B82F6)),
        SizedBox(height: 12),
        Text('통화 대기 중', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        SizedBox(height: 6),
        Text('전화 버튼을 눌러 분석을 시작하세요', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      ]),
    );
  }

  Widget _buildResultCard(AnalysisResult r) {
    final level = r.warningLevel.clamp(0, 3);
    final color = _levelColors[level];
    final bgColor = _levelBgColors[level];
    final label = _levelLabels[level];
    final icon = _levelIcons[level];

    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text('${r.riskScore}점', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            ),
          ]),
          if (r.isFakeVoice) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFDC2626).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Text('합성 음성 감지됨', style: TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
            ),
          ],
          if (r.detectedLabels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: r.detectedLabels.map((l) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
                child: Text(l, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              )).toList(),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.mic_rounded, size: 14, color: Color(0xFF3B82F6)),
            SizedBox(width: 6),
            Text('인식된 텍스트', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
          ]),
          const SizedBox(height: 8),
          Text('"${r.text}"', style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), height: 1.5)),
        ]),
      ),
      if (r.explanation.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.smart_toy_rounded, size: 14, color: Color(0xFF8B5CF6)),
              SizedBox(width: 6),
              Text('AI 분석', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            ]),
            const SizedBox(height: 8),
            Text(r.explanation, style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5)),
          ]),
        ),
      ],
    ]);
  }
}
