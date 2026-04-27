import pyaudio
import numpy as np
import queue
import threading
import time
from faster_whisper import WhisperModel

# 설정
SAMPLE_RATE = 16000
CHANNELS = 1
FORMAT = pyaudio.paInt16
CHUNK_SIZE = 1024
RECORD_SECONDS = 2.0
SILENCE_THRESHOLD = 500
WINDOW_SECONDS = 8.0

# 모델 로드
model = WhisperModel("small", device="cpu", compute_type="int8") # device="cuda"
audio_queue = queue.Queue()


''' 마이크 입력 '''
def capture_audio(stop_event):
    pa = pyaudio.PyAudio()
    stream = pa.open(
        format=FORMAT, channels=CHANNELS,
        rate=SAMPLE_RATE, input=True,
        frames_per_buffer=CHUNK_SIZE,
    )
    frames_per_segment = int(SAMPLE_RATE * RECORD_SECONDS)
    buffer = []

    try:
        while not stop_event.is_set():
            raw = stream.read(CHUNK_SIZE, exception_on_overflow=False)
            pcm = np.frombuffer(raw, dtype=np.int16)
            buffer.extend(pcm.tolist())

            if len(buffer) >= frames_per_segment:
                segment = np.array(buffer[:frames_per_segment], dtype=np.int16)
                audio_queue.put((segment, time.time()))  # 타임스탬프 같이 전달
                buffer = buffer[frames_per_segment // 2:]
    finally:
        stream.stop_stream()
        stream.close()
        pa.terminate()


def is_speech(audio_int16):
    rms = np.sqrt(np.mean(audio_int16.astype(np.float32) ** 2))
    return rms > SILENCE_THRESHOLD


# ── 슬라이딩 윈도우 + 중복 제거 ──────────────────────
window_samples = int(SAMPLE_RATE * WINDOW_SECONDS)
audio_window = np.array([], dtype=np.int16)
prev_text = ""

def postprocess(text: str) -> str:
    """이전 결과와 겹치는 앞부분 제거."""
    global prev_text
    if text.startswith(prev_text):
        new_part = text[len(prev_text):].strip()
    else:
        new_part = text.strip()
    prev_text = text
    return new_part


def transcribe_audio(stop_event, result_callback):
    global audio_window

    while not stop_event.is_set():
        try:
            segment_int16, enqueue_time = audio_queue.get(timeout=1.0)
        except queue.Empty:
            continue

        # 큐에 밀린 세그먼트가 있으면 최신 것만 사용
        dropped = 0
        while not audio_queue.empty():
            try:
                segment_int16, enqueue_time = audio_queue.get_nowait()
                dropped += 1
            except queue.Empty:
                break

        # 지연이 2초 초과면 윈도우 리셋 후 스킵
        current_latency = time.time() - enqueue_time
        if current_latency > 2.0:
            audio_window = np.array([], dtype=np.int16)
            continue

        if not is_speech(segment_int16):
            continue

        # 슬라이딩 윈도우에 누적
        audio_window = np.concatenate([audio_window, segment_int16])
        if len(audio_window) > window_samples:
            audio_window = audio_window[-window_samples:]

        audio_float32 = audio_window.astype(np.float32) / 32768.0

        segments, _ = model.transcribe(
            audio_float32,
            language="ko",
            beam_size=5,
            vad_filter=True,
            vad_parameters={
                "min_silence_duration_ms": 300,
                "speech_pad_ms": 100,
            },
        )

        full_text = "".join(seg.text for seg in segments).strip()
        if not full_text:
            continue

        new_part = postprocess(full_text)
        if new_part:
            result_callback(new_part)


# 실시간 STT 변환 후 데이터 넘겨주는 함수 (어떤식으로 데이터 넘길지 의논필요)
def on_transcribed(text: str):
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{timestamp}] {text}")
    # TODO: 판별 모델 호출


if __name__ == "__main__":
    stop_event = threading.Event()
    t_capture = threading.Thread(target=capture_audio, args=(stop_event,), daemon=True)
    t_stt = threading.Thread(target=transcribe_audio, args=(stop_event, on_transcribed), daemon=True)

    t_capture.start()
    t_stt.start()

    print("실시간 STT 시작 — 종료하려면 Ctrl+C")
    try:
        while True:
            time.sleep(0.1)
    except KeyboardInterrupt:
        stop_event.set()

    t_capture.join(timeout=3)
    t_stt.join(timeout=3)