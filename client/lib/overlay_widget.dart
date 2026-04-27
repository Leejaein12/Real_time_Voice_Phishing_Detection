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
  int _warningLevel = 0;
  String _text = '분석 중...';

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
          _warningLevel = (data['warning_level'] as int? ?? 0).clamp(0, 3);
          _text = data['text'] as String? ?? '분석 중...';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColors[_warningLevel];
    final bgColor = _levelBgColors[_warningLevel];
    final icon = _levelIcons[_warningLevel];
    final label = _levelLabels[_warningLevel];

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
              BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left accent strip with shield branding
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
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Text(
                                'Vaia',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3B82F6),
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              _text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF374151)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Close hint
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.close_rounded, size: 14, color: const Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
