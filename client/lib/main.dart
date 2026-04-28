import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/call_record.dart';
import 'models/analysis_result.dart';
import 'services/websocket_service.dart';
import 'services/audio_stream_service.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoicePhishingApp());
}

class VoicePhishingApp extends StatelessWidget {
  const VoicePhishingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vaia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6), brightness: Brightness.dark),
        textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final List<CallRecord> _records = [];
  bool _isProtectionOn = false;
  double _textScale = 1.0;
  DateTime? _callStartTime;
  AnalysisResult? _lastResult;

  final _ws = WebSocketService();
  late final _audio = AudioStreamService(_ws);

  @override
  void initState() {
    super.initState();
    _loadProtectionState();
    _setupCallCallbacks();
    _audio.startPhoneEventListening();
  }

  void _setupCallCallbacks() {
    _audio.onIncomingNumber = (_) {};  // 수신 번호 — 필요 시 HomeScreen으로 전달

    _audio.onCallStarted = () {};

    _audio.onCallConnected = () {
      if (!_isProtectionOn) return;
      _callStartTime = DateTime.now();
      _ws.connect(
        onResult: (result) {
          setState(() => _lastResult = result);
          if (Platform.isAndroid) {
            FlutterOverlayWindow.shareData({
              'warning_level': result.warningLevel,
              'score': result.riskScore,
              'text': result.text,
              'reason': result.explanation,
            });
          }
        },
        onDisconnected: () {},
      );
      _audio.start();
    };

    _audio.onCallEnded = () async {
      if (_callStartTime == null) return;
      final duration = DateTime.now().difference(_callStartTime!);
      await _audio.stop();
      _ws.disconnect();
      final result = _lastResult;
      setState(() {
        if (result != null) {
          _records.add(CallRecord.fromResult(result, duration));
        }
        _callStartTime = null;
        _lastResult = null;
      });
    };
  }

  Future<void> _loadProtectionState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _isProtectionOn = prefs.getBool('isProtectionOn') ?? false);
  }

  Future<void> _saveProtectionState(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isProtectionOn', value);
  }

  @override
  void dispose() {
    _audio.dispose();
    _ws.disconnect();
    super.dispose();
  }

  Future<void> _toggleProtection() async {
    final turningOn = !_isProtectionOn;
    setState(() => _isProtectionOn = turningOn);
    await _saveProtectionState(turningOn);

    if (!Platform.isAndroid) return;

    if (turningOn) {
      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        await FlutterOverlayWindow.requestPermission();
        return;
      }
      await FlutterOverlayWindow.showOverlay(
        height: 120,
        width: -1,
        alignment: OverlayAlignment.topCenter,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Vaia 보호 중',
        overlayContent: '실시간 보이스피싱 탐지 활성화',
        enableDrag: true,
        positionGravity: PositionGravity.auto,
      );
    } else {
      // 보호 끄기: 통화 중 녹음이 진행 중이면 중단
      if (_callStartTime != null) {
        await _audio.stop();
        _ws.disconnect();
        setState(() {
          _callStartTime = null;
          _lastResult = null;
        });
      }
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        records: _records,
        isProtectionOn: _isProtectionOn,
        onToggle: _toggleProtection,
      ),
      HistoryScreen(records: _records),
      StatisticsScreen(records: _records),
      SettingsScreen(
        textScale: _textScale,
        onScaleSelect: (scale) => setState(() => _textScale = scale),
        audio: _audio,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      extendBody: true,
      body: Stack(
        children: [
          const _AppBackground(),
          MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScale)),
            child: SafeArea(bottom: false, child: screens[_currentIndex]),
          ),
        ],
      ),
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}


class _AppBackground extends StatelessWidget {
  const _AppBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF0F4FF), Color(0xFFEEF2FF), Color(0xFFEBF0FF)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          top: -100, right: -80,
          child: Container(
            width: 320, height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF3B82F6).withValues(alpha: 0.18),
                const Color(0xFF3B82F6).withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        Positioned(
          top: 280, left: -80,
          child: Container(
            width: 240, height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                const Color(0xFF8B5CF6).withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: 220, right: -60,
          child: Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                const Color(0xFF06B6D4).withValues(alpha: 0.12),
                const Color(0xFF06B6D4).withValues(alpha: 0),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _FloatingNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + bottomPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: '홈', selected: currentIndex == 0, onTap: () => onTap(0)),
                _NavItem(icon: Icons.history_rounded, label: '이력', selected: currentIndex == 1, onTap: () => onTap(1)),
                _NavItem(icon: Icons.bar_chart_rounded, label: '통계', selected: currentIndex == 2, onTap: () => onTap(2)),
                _NavItem(icon: Icons.settings_rounded, label: '설정', selected: currentIndex == 3, onTap: () => onTap(3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.white : const Color(0xFF94A3B8), size: 20),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: selected
                  ? Row(children: [
                      const SizedBox(width: 6),
                      Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ])
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
