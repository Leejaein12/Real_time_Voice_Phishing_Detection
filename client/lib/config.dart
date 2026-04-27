class AppConfig {
  // 환경에 맞게 변경 후 빌드
  // Windows 데모  : ws://localhost:8000/ws/audio
  // Android 에뮬  : ws://10.0.2.2:8000/ws/audio
  // 실기기         : ws://[서버 IP]:8000/ws/audio
  static const String wsUrl = 'ws://localhost:8000/ws/audio';
}
