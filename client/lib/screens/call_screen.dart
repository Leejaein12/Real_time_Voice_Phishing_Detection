import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/whisper_stt_service.dart';
import '../models/analysis_result.dart';

enum _Phase { downloading, ringing, active, ended }

class CallScreen extends StatefulWidget {
  /// assets/audio/ 안의 WAV 파일명 (예: 'sample.wav')
  /// 변환: ffmpeg -i input.mp4 -ar 16000 -ac 1 -c:a pcm_s16le output.wav
  final String audioAsset;
  final String callerName;
  final String callerNumber;

  const CallScreen({
    super.key,
    required this.audioAsset,
    this.callerName = '알 수 없음',
    this.callerNumber = '010-0000-0000',
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  _Phase _phase = _Phase.ringing;

  final _player = AudioPlayer();
  final _stt = WhisperSttService.instance;

  // STT 결과
  String _fullText = '';
  String _displayText = '';
  int _warningLevel = 0;
  bool _isTranscribing = false;
  String? _errorMsg;
  String? _tempWavPath;
  bool _chunkCancelled = false;

  // 타이머
  Duration _elapsed = Duration.zero;
  Timer? _callTimer;

  // 모델 다운로드
  double _downloadProgress = 0;

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
    _checkModelAndInit();
  }

  @override
  void dispose() {
    _chunkCancelled = true;
    _callTimer?.cancel();
    _player.dispose();
    _ringCtrl.dispose();
    _pulseCtrl.dispose();
    if (_tempWavPath != null) {
      final f = File(_tempWavPath!);
      if (f.existsSync()) f.deleteSync();
    }
    super.dispose();
  }

  // ── 모델 확인 ──────────────────────────────────────────────
  Future<void> _checkModelAndInit() async {
    final downloaded = await _stt.isModelDownloaded();
    if (!downloaded) {
      setState(() => _phase = _Phase.downloading);
      await _downloadModel();
    } else if (!_stt.isReady) {
      await _stt.initialize();
    }
    if (mounted && _phase == _Phase.downloading) {
      setState(() => _phase = _Phase.ringing);
    }
  }

  Future<void> _downloadModel() async {
    try {
      await _stt.downloadModel(
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      await _stt.initialize();
    } catch (e) {
      if (mounted) setState(() => _errorMsg = '모델 다운로드 실패: $e');
    }
  }

  // ── 전화 받기 ──────────────────────────────────────────────
  Future<void> _answerCall() async {
    setState(() => _phase = _Phase.active);
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
    // 재생과 STT 동시 시작 (서로 대기하지 않음)
    unawaited(_startPlayback());
    unawaited(_startStt());
  }

  Future<void> _startPlayback() async {
    try {
      await _player.setAsset('assets/audio/${widget.audioAsset}');
      await _player.play();
    } catch (_) {}
  }

  // ── 청크 단위 실시간 STT ──────────────────────────────────
  Future<void> _startStt() async {
    if (!_stt.isReady) {
      if (mounted) setState(() => _errorMsg = '모델 준비 중...');
      return;
    }
    if (mounted) setState(() => _isTranscribing = true);
    _chunkCancelled = false;

    try {
      _tempWavPath =
          await _stt.copyAssetToTemp('assets/audio/${widget.audioAsset}');
      final wavBytes = await File(_tempWavPath!).readAsBytes();

      final dataOffset = _findDataOffset(wavBytes);
      final sampleRate = _parseSampleRate(wavBytes);
      final pcm = wavBytes.sublist(dataOffset);

      // 6초 청크 (16kHz mono 16-bit = sampleRate * 2 bytes/s)
      final chunkSize = 6 * sampleRate * 2;

      var offset = 0;
      while (offset < pcm.length && !_chunkCancelled) {
        final end = (offset + chunkSize).clamp(0, pcm.length);
        final chunk = pcm.sublist(offset, end);

        try {
          final text =
              await _stt.transcribeChunk(chunk, sampleRate: sampleRate);
          if (text.isNotEmpty && mounted && !_chunkCancelled) {
            setState(() {
              _fullText += (_fullText.isEmpty ? '' : ' ') + text;
              _displayText = _fullText;
            });
            _updateWarningLevel(_fullText);
          }
        } catch (_) {
          // 청크 오류 시 다음 청크로 계속 진행
        }

        offset = end;
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = 'STT 오류: $e');
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  // WAV 헤더에서 "data" 청크 시작 위치 탐색
  int _findDataOffset(Uint8List wav) {
    for (var i = 12; i < wav.length - 8; i++) {
      if (wav[i] == 0x64 &&
          wav[i + 1] == 0x61 &&
          wav[i + 2] == 0x74 &&
          wav[i + 3] == 0x61) {
        return i + 8; // "data" + 4바이트 크기 필드 스킵
      }
    }
    return 44; // 표준 WAV 헤더 폴백
  }

  // WAV 헤더 바이트 24-27에서 샘플레이트 파싱 (little-endian)
  int _parseSampleRate(Uint8List wav) {
    return wav[24] | (wav[25] << 8) | (wav[26] << 16) | (wav[27] << 24);
  }

  void _updateWarningLevel(String text) {
    const highRisk = [
      '검찰', '경찰', '금융감독원', '계좌이체', '현금', '개인정보', '카드번호', '비밀번호', '대출', '구속'
    ];
    const midRisk = ['확인', '승인', '처리', '사건', '범죄', '피해', '명의'];
    var score = 0;
    for (final kw in highRisk) {
      if (text.contains(kw)) score += 20;
    }
    for (final kw in midRisk) {
      if (text.contains(kw)) score += 10;
    }
    final level = (score ~/ 20).clamp(0, 3);
    if (level != _warningLevel) setState(() => _warningLevel = level);
  }

  // ── 전화 끊기 ──────────────────────────────────────────────
  Future<void> _endCall() async {
    _chunkCancelled = true;
    _callTimer?.cancel();
    await _player.stop();
    setState(() {
      _phase = _Phase.ended;
      _displayText = _fullText;
    });
    _updateWarningLevel(_fullText);
  }

  void _popWithResult() {
    Navigator.of(context).pop(AnalysisResult(
      text: _fullText.isEmpty ? '(인식된 텍스트 없음)' : _fullText,
      riskScore: _warningLevel * 25,
      warningLevel: _warningLevel,
      explanation: '',
    ));
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.downloading => _buildDownloading(),
          _Phase.ringing     => _buildRinging(),
          _Phase.active      => _buildActive(),
          _Phase.ended       => _buildEnded(),
        },
      ),
    );
  }

  // ── 모델 다운로드 화면 ─────────────────────────────────────
  Widget _buildDownloading() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.download_rounded, color: Colors.white54, size: 56),
          const SizedBox(height: 24),
          const Text('STT 모델 다운로드 중',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('ggml-base (142MB) — 최초 1회',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
          const SizedBox(height: 32),
          if (_errorMsg != null)
            Text(_errorMsg!, style: const TextStyle(color: Color(0xFFEF4444)))
          else ...[
            LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              backgroundColor: Colors.white12,
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 12),
            Text(
              _downloadProgress > 0
                  ? '${(_downloadProgress * 100).toStringAsFixed(1)}%'
                  : '연결 중...',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ],
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
                  color: Colors.white.withValues(alpha: 0.05 * (1 - _ringCtrl.value)),
                ),
              ),
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.person, color: Colors.white70, size: 44),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text(widget.callerName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.callerNumber,
              style: const TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('수신 전화',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
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

  // ── 통화 중 화면 ───────────────────────────────────────────
  Widget _buildActive() {
    final mm = _elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        const SizedBox(height: 20),
        Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1)),
            child: const Icon(Icons.person, color: Colors.white70, size: 32),
          ),
          const SizedBox(height: 10),
          Text(widget.callerName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$mm:$ss',
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
        ]),
        const SizedBox(height: 16),
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
                        style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const Spacer(),
                    if (_isTranscribing)
                      const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white38),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(
                        _errorMsg ??
                            (_displayText.isEmpty
                                ? (_isTranscribing ? '분석 중...' : '대기 중')
                                : _displayText),
                        style: TextStyle(
                          color: _errorMsg != null
                              ? const Color(0xFFEF4444)
                              : Colors.white,
                          fontSize: 15,
                          height: 1.7,
                        ),
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
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                      const SizedBox(height: 10),
                      Text(
                        _fullText.isEmpty ? '(인식된 텍스트 없음)' : _fullText,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14, height: 1.7),
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
          width: size, height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: Colors.white, size: size * 0.45),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
