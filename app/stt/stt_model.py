import numpy as np
from faster_whisper import WhisperModel

SAMPLE_RATE = 16000
SILENCE_THRESHOLD = 500
WINDOW_SECONDS = 8.0


class STTModel:
    def __init__(self, model_size="small", device="cpu", compute_type="int8", language="ko"):
        self.model = WhisperModel(model_size, device=device, compute_type=compute_type)
        self.language = language
        self.window_samples = int(SAMPLE_RATE * WINDOW_SECONDS)
        self.audio_window = np.array([], dtype=np.int16)
        self.prev_text = ""

    def _is_speech(self, audio_int16: np.ndarray) -> bool:
        rms = np.sqrt(np.mean(audio_int16.astype(np.float32) ** 2))
        return rms > SILENCE_THRESHOLD

    def _postprocess(self, text: str) -> str:
        """이전 결과와 겹치는 앞부분 제거."""
        prev_words = self.prev_text.split()
        curr_words = text.split()
        overlap = 0
        for n in range(min(len(prev_words), len(curr_words), 10), 0, -1):
            if prev_words[-n:] == curr_words[:n]:
                overlap = n
                break
        new_part = " ".join(curr_words[overlap:]).strip()
        self.prev_text = text
        return new_part

    def reset(self):
        """윈도우 및 이전 텍스트 초기화 (지연 발생 시 외부에서 호출)"""
        self.audio_window = np.array([], dtype=np.int16)
        self.prev_text = ""

    def transcribe(self, audio_chunk: bytes) -> str:
        """
        audio_chunk : pyaudio에서 읽은 raw bytes (int16, 16000Hz, mono)
        return      : 새로 인식된 텍스트. 무음이거나 새 내용 없으면 ""
        """
        segment_int16 = np.frombuffer(audio_chunk, dtype=np.int16)

        if not self._is_speech(segment_int16):
            return ""

        # 슬라이딩 윈도우에 누적
        self.audio_window = np.concatenate([self.audio_window, segment_int16])
        if len(self.audio_window) > self.window_samples:
            self.audio_window = self.audio_window[-self.window_samples:]

        audio_float32 = self.audio_window.astype(np.float32) / 32768.0

        segments, _ = self.model.transcribe(
            audio_float32,
            language=self.language,
            beam_size=5,
            vad_filter=True,
            vad_parameters={
                "min_silence_duration_ms": 300,
                "speech_pad_ms": 100,
            },
        )

        full_text = "".join(seg.text for seg in segments).strip()
        if not full_text:
            return ""

        return self._postprocess(full_text)