import pyaudio
import numpy as np
import queue
import threading
import time
from faster_whisper import WhisperModel


SAMPLE_RATE = 16000
CHANNELS = 1
FORMAT = pyaudio.paInt16
CHUNK_SIZE = 1024
RECORD_SECONDS = 1.0        # 2.0 → 1.0 (딜레이 감소)
WINDOW_SECONDS = 5.0        # 8.0 → 5.0 (딜레이 감소)
SILENCE_THRESHOLD = 200     # RMS는 유지하되 threshold 낮춰 관대하게


class STTModel:
    def __init__(self, model_size: str = "small", device: str = "cpu", compute_type: str = "int8"):
        self.model = WhisperModel(model_size, device=device, compute_type=compute_type)
        self.window_samples = int(SAMPLE_RATE * WINDOW_SECONDS)
        self.frames_per_segment = int(SAMPLE_RATE * RECORD_SECONDS)

        self.audio_window = np.array([], dtype=np.int16)
        self.prev_text = ""
        self.audio_queue = queue.Queue()
        self._buffer = np.array([], dtype=np.int16)  # list → numpy array

        self._stop_event = threading.Event()
        self._t_capture = None
        self._t_transcribe = None

    # ── 내부 유틸 ──────────────────────────────────────────

    def _is_speech(self, audio_int16: np.ndarray) -> bool:
        # threshold 낮춰서 작은 발화도 통과
        rms = np.sqrt(np.mean(audio_int16.astype(np.float32) ** 2))
        return rms > SILENCE_THRESHOLD

    def _postprocess(self, text: str) -> str:
        # word overlap 방식으로 중복 제거
        # Whisper는 조사/어미가 미묘하게 바뀌므로 문자 단위보다 단어 단위가 더 안정적
        prev_words = self.prev_text.split()
        curr_words = text.split()

        best_overlap = 0
        max_check = min(len(prev_words), len(curr_words), 10)

        for n in range(max_check, 1, -1):  # 최소 2단어 이상 겹쳐야 인정
            if prev_words[-n:] == curr_words[:n]:
                best_overlap = n
                break

        new_part = " ".join(curr_words[best_overlap:]).strip()
        self.prev_text = text
        return new_part

    def _reset_window(self):
        self.audio_window = np.array([], dtype=np.int16)
        self.prev_text = ""

    # ── 마이크 캡처 ────────────────────────────────────────

    def _capture_audio(self):
        pa = pyaudio.PyAudio()
        stream = pa.open(
            format=FORMAT, channels=CHANNELS,
            rate=SAMPLE_RATE, input=True,
            frames_per_buffer=CHUNK_SIZE,
        )
        try:
            while not self._stop_event.is_set():
                raw = stream.read(CHUNK_SIZE, exception_on_overflow=False)
                pcm = np.frombuffer(raw, dtype=np.int16)

                # 5번: numpy concatenate로 버퍼 관리
                self._buffer = np.concatenate([self._buffer, pcm])

                while len(self._buffer) >= self.frames_per_segment:
                    segment = self._buffer[:self.frames_per_segment]
                    self.audio_queue.put((segment.copy(), time.time()))
                    self._buffer = self._buffer[self.frames_per_segment // 2:]
        finally:
            stream.stop_stream()
            stream.close()
            pa.terminate()

    # ── 변환 루프 ──────────────────────────────────────────

    def _transcribe_audio(self, result_callback):
        while not self._stop_event.is_set():
            try:
                segment_int16, enqueue_time = self.audio_queue.get(timeout=1.0)
            except queue.Empty:
                continue

            # 3번: 밀린 세그먼트는 최대 2개까지 유지, 나머지 드롭
            while self.audio_queue.qsize() > 2:
                try:
                    segment_int16, enqueue_time = self.audio_queue.get_nowait()
                except queue.Empty:
                    break

            # 4번: 지연 초과 시 window reset 없이 skip만
            if time.time() - enqueue_time > 2.0:
                continue

            if not self._is_speech(segment_int16):
                continue

            # 슬라이딩 윈도우에 누적
            self.audio_window = np.concatenate([self.audio_window, segment_int16])
            if len(self.audio_window) > self.window_samples:
                self.audio_window = self.audio_window[-self.window_samples:]

            audio_float32 = self.audio_window.astype(np.float32) / 32768.0

            segments, _ = self.model.transcribe(
                audio_float32,
                language="ko",
                beam_size=5,
                vad_filter=True,      # Whisper VAD 유지
                vad_parameters={
                    "min_silence_duration_ms": 300,
                    "speech_pad_ms": 100,
                },
            )

            full_text = "".join(seg.text for seg in segments).strip()
            if not full_text:
                continue

            new_part = self._postprocess(full_text)
            if new_part:
                result_callback(new_part)

    # ── 시작 / 종료 ────────────────────────────────────────

    def start(self, result_callback):
        """마이크 캡처 + 변환 루프 스레드 시작."""
        self._stop_event.clear()
        self._t_capture = threading.Thread(target=self._capture_audio, daemon=True)
        self._t_transcribe = threading.Thread(target=self._transcribe_audio, args=(result_callback,), daemon=True)
        self._t_capture.start()
        self._t_transcribe.start()

    def stop(self, timeout: float = 3.0):
        """마이크 캡처 + 변환 루프 스레드 종료."""
        self._stop_event.set()
        if self._t_capture:
            self._t_capture.join(timeout=timeout)
        if self._t_transcribe:
            self._t_transcribe.join(timeout=timeout)