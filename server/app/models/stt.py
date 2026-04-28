import numpy as np
from faster_whisper import WhisperModel

_SAMPLE_RATE = 16000
_SILENCE_THRESHOLD = 500
_WINDOW_SECONDS = 8.0
_window_samples = int(_SAMPLE_RATE * _WINDOW_SECONDS)


class STTModel:
    def __init__(self):
        self._model = WhisperModel("small", device="cpu", compute_type="int8")
        self._audio_window = np.array([], dtype=np.int16)
        self._prev_text = ""

    def transcribe(self, audio_chunk: bytes) -> str:
        segment = np.frombuffer(audio_chunk, dtype=np.int16)

        if not self._is_speech(segment):
            return ""

        self._audio_window = np.concatenate([self._audio_window, segment])
        if len(self._audio_window) > _window_samples:
            self._audio_window = self._audio_window[-_window_samples:]

        audio_float32 = self._audio_window.astype(np.float32) / 32768.0

        segments, _ = self._model.transcribe(
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
            return ""

        return self._postprocess(full_text)

    def _is_speech(self, audio_int16: np.ndarray) -> bool:
        rms = np.sqrt(np.mean(audio_int16.astype(np.float32) ** 2))
        return rms > _SILENCE_THRESHOLD

    def _postprocess(self, text: str) -> str:
        if text.startswith(self._prev_text):
            new_part = text[len(self._prev_text):].strip()
        else:
            new_part = text.strip()
        self._prev_text = text
        return new_part
