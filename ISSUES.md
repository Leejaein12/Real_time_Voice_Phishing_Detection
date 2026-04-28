# 현재 문제 목록 및 해결 방안 (2026-04-28)

---

## 1. 오디오 데이터가 서버에 안 도달함 ⚠️ 핵심 버그

**뭔 상황이냐:**
앱에서 토글 켜면 서버랑 WebSocket 연결은 됨. 근데 말을 해도 서버 쪽에서 오디오를 하나도 못 받음.
서버 로그에 "연결됐다"는 뜨는데 그 다음에 아무것도 안 찍힘.

**왜 이런 일이 생기냐:**
Android에서 마이크 녹음을 시작할 때 `hasPermission()`이라는 걸 먼저 체크함.
만약 권한이 없으면 녹음 시작 코드가 그냥 통과되고 끝남. 근데 앱이 뭔가 잘못됐다고 알려주지 않아서 모름.
통화 중에는 Android가 마이크를 독점해버리는 경우도 있음.

**어떻게 확인하냐:**
방금 로그 추가해놨음. 터미널에서 `r` 눌러 hot reload → 토글 켜면 아래 로그 확인:
- `[AUDIO] hasPermission=false` → 권한 문제
- `[AUDIO] hasPermission=true` + `[WS] sendAudio`가 안 찍히면 → 스트림 시작 실패
- `[WS] sendAudio connected=false` → WebSocket 상태 문제

**해결 방안:**

**케이스 A: 권한 문제일 때**
`audio_stream_service.dart`의 `start()` 안에서 권한을 직접 요청하도록 수정:
```dart
Future<void> start() async {
  if (!await _recorder.hasPermission()) {
    // 권한 없으면 그냥 return 말고 권한 요청까지 해야 함
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
  }
  ...
}
```
또는 `main.dart`에서 `_toggleProtection()` 실행 전에 권한 체크 먼저.

**케이스 B: 통화 중 마이크 독점일 때**
`record` 패키지 `RecordConfig`의 `androidConfig` 에서 오디오 소스를 바꿔야 함:
```dart
final stream = await _recorder.startStream(
  RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication, // MIC 대신 이걸로
    ),
  ),
);
```
`voiceCommunication`은 통화 중에도 마이크 접근이 가능한 오디오 소스임.

**관련 파일:**
- `client/lib/services/audio_stream_service.dart`
- `client/lib/services/websocket_service.dart`

---

## 2. 전화할 때 상대방 목소리가 잡히는지 모름

**뭔 상황이냐:**
보이스피싱 탐지 앱이니까 상대방 목소리도 서버에 보내야 함.
근데 지금 내 목소리만 잡히는 건지, 상대방 것도 잡히는 건지 확인이 안 됨.

**왜 이게 어렵냐:**
Android에서 통화 양쪽 목소리를 동시에 녹음하는 건 시스템 권한(`CAPTURE_AUDIO_OUTPUT`)이 필요함.
일반 앱은 그 권한을 못 받음 — 구글 정책상 막혀있음.

그래서 현재 쓰는 꼼수: 통화 시작할 때 스피커폰을 강제로 켬 → 상대방 목소리가 스피커에서 나오면 마이크가 그 소리를 물리적으로 줍는 방식.
근데 전화가 시작되면 Android 전화 시스템이 오디오 모드를 자기 방식으로 바꿔버리면서 스피커폰이 꺼질 수 있음.

**해결 방안:**

`CallReceiver.kt`에서 통화 연결됐을 때(`OFFHOOK`) 스피커폰을 다시 켜는 코드 추가:
```kotlin
TelephonyManager.EXTRA_STATE_OFFHOOK -> {
    if (isProtectionOn) {
        // 앱 실행 + 스피커폰 재활성화
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.mode = AudioManager.MODE_IN_CALL
        audioManager.isSpeakerphoneOn = true

        val launchIntent = ...
        if (launchIntent != null) context.startActivity(launchIntent)
    }
}
```
`MODE_IN_CALL`은 실제 통화 중 오디오 모드이고, 이 상태에서 스피커폰 켜면 상대 목소리가 스피커로 나와서 마이크가 잡을 수 있음.

통화 끊겼을 때(`IDLE`)는 스피커폰 다시 끄는 코드도 추가해야 함.

**관련 파일:**
- `client/android/app/src/main/kotlin/com/voiceguard/app/CallReceiver.kt`
- `client/android/app/src/main/kotlin/com/voiceguard/app/MainActivity.kt`

---

## 3. 오버레이가 화면에 안 보임

**뭔 상황이냐:**
보호 토글 켜도 화면 위에 Vaia 배너가 안 뜸.

**지금까지 뭘 고쳤냐:**
- AndroidManifest 서비스 클래스명 오타 수정 → 서비스 시작은 됨
- Android 14 크래시 → `targetSdk = 33`으로 낮춰서 해결 (임시)
- 오버레이 창 생성은 됨 (프레임 렌더링 확인)
- `SizedBox.expand()` 추가 → 위젯이 공간 꽉 채우게

**남은 의심 및 해결 방안:**

**확인 먼저:**
Vaia 앱 말고 다른 앱(카카오톡, 유튜브 등) 실행 중에 오버레이가 보이는지 확인.
Samsung One UI는 현재 포그라운드 앱 위에 자기 오버레이 못 올리는 경우 있음.
다른 앱에서도 안 보이면 → 코드 문제.

**코드 문제일 때:**
`main.dart`에서 `showOverlay()` 호출할 때 `height: 120`인데, 오버레이 창 높이가 실제로는 더 작을 수 있음.
`height: WindowSize.fullCover` 또는 더 큰 값으로 바꿔서 테스트.

**Android 14 완전 해결 방안 (targetSdk 33 임시방편 없애려면):**
`flutter_overlay_window` 플러그인 소스 직접 패치 필요.
`android/app/build.gradle.kts`에서 `targetSdk`를 다시 올리고,
`AndroidManifest.xml`의 오버레이 서비스에 타입 추가:
```xml
<service
    android:name="flutter.overlay.window.flutter_overlay_window.OverlayService"
    android:exported="false"
    android:foregroundServiceType="specialUse"/>
```
그리고 플러그인 소스를 로컬 복사본으로 오버라이드해서 `startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)` 형식으로 패치.

**관련 파일:**
- `client/lib/overlay_widget.dart`
- `client/lib/main.dart`
- `client/android/app/src/main/AndroidManifest.xml`
- `client/android/app/build.gradle.kts`

---

## 4. WebSocket 연결이 끊기면 자동으로 다시 안 연결됨

**뭔 상황이냐:**
토글 켜서 서버랑 연결했는데 중간에 끊기면 자동 재연결 없음.
토글 껐다 다시 켜야 재연결됨.

**해결 방안:**
`WebSocketService`에 재연결 로직 추가:
```dart
void _onDisconnected() {
  _isConnected = false;
  // 3초 후 재시도
  Future.delayed(const Duration(seconds: 3), () {
    if (!_isConnected) connect(onResult: _onResult, onDisconnected: _onDisconnected);
  });
}
```
`connect()` 호출할 때 콜백을 멤버 변수로 저장해두면 재연결 때 그대로 쓸 수 있음.
재시도 횟수 제한(예: 5회)도 같이 넣는 게 좋음. 서버가 꺼진 상태면 무한 루프 돎.

**관련 파일:**
- `client/lib/services/websocket_service.dart`

---

## 5. Docker 메모리 설정 안 올림

**뭔 상황이냐:**
AI 모델 3개를 올리면 메모리를 많이 먹음. STT를 작은 모델로 바꿔서 일단 해결했는데,
Docker Desktop 메모리 한도는 아직 안 올렸음. 나중에 또 죽을 수 있음.

**해결 방안:**
Docker Desktop 앱 열기 → 우측 상단 Settings 아이콘 → Resources → Memory 슬라이더 → **4096 MB(4GB) 이상**으로 설정 → Apply & Restart

---

## 해결 완료 ✅

| 문제 | 어떻게 고쳤냐 |
|------|--------------|
| 앱 시작 시 토글 자동 ON | 앱 켤 때마다 항상 꺼진 상태로 시작하게 초기화 |
| IP 주소 코드에 하드코딩 | 설정 화면에서 IP 직접 입력하고 저장하도록 변경 |
| WebSocket 연결 결과 로그 없음 | 연결 성공/실패 로그 추가 |
| 서버 환경변수 오류 (KMP_DUPLICATE_LIB_OK) | .env 파일에서 docker-compose.yml 환경변수로 이동 |
| 서버 메모리 부족으로 강제 종료 | STT 모델 small → tiny로 교체 (메모리 약 500MB 절약) |
