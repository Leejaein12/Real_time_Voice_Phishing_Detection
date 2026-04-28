import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

@pragma('vm:entry-point')
void overlayMain() {
  runApp(const _OverlayApp());
}

class _OverlayApp extends StatelessWidget {
  const _OverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayView(),
    );
  }
}

class OverlayView extends StatefulWidget {
  const OverlayView({super.key});

  @override
  State<OverlayView> createState() => _OverlayViewState();
}

class _OverlayViewState extends State<OverlayView> {
  int _level = 0;
  int _score = 0;
  String _text = '분석 중...';
  String? _reason;

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
  static const _levelIcons = [
    Icons.check_circle_rounded,
    Icons.warning_amber_rounded,
    Icons.warning_amber_rounded,
    Icons.dangerous_rounded,
  ];
  static const _levelLabels = ['안전', '주의', '경고', '위험'];

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map) {
        setState(() {
          _level = ((data['warning_level'] as int?) ?? 0).clamp(0, 3);
          _score = (data['score'] as int?) ?? 0;
          _text = (data['text'] as String?) ?? '분석 중...';
          _reason = data['reason'] as String?;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColors[_level];
    final bgColor = _levelBgColors[_level];
    final icon = _levelIcons[_level];
    final label = _levelLabels[_level];
    final hasReason = _reason != null && _reason!.isNotEmpty;

    return GestureDetector(
      onTap: () => FlutterOverlayWindow.closeOverlay(),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4)),
              if (_level >= 2)
                BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: 2),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 왼쪽 파란 방패 스트립
              Container(
                width: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(17),
                    bottomLeft: Radius.circular(17),
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.shield, color: Colors.white, size: 20),
                ),
              ),
              // 본문
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 상단: 레벨 배지 + 점수
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: color.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(icon, color: color, size: 11),
                            const SizedBox(width: 3),
                            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        if (_score > 0)
                          Text(
                            '위험도 $_score',
                            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                          ),
                        const Spacer(),
                        const Text('Vaia', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
                      ]),
                      const SizedBox(height: 5),
                      // 전사 텍스트
                      Text(
                        '"$_text"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF374151), fontStyle: FontStyle.italic),
                      ),
                      // 위험 이유 (경고 이상일 때)
                      if (hasReason) ...[
                        const SizedBox(height: 5),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.smart_toy_rounded, color: color, size: 11),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _reason!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: color, height: 1.4),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
              // 닫기 힌트
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Icon(Icons.close_rounded, size: 13, color: const Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
