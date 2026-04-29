import numpy as np
from faster_whisper import WhisperModel

_SAMPLE_RATE = 16000
_WINDOW_SECONDS = 8.0
_WINDOW_SAMPLES = int(_SAMPLE_RATE * _WINDOW_SECONDS)


class STTModel:
    def __init__(self):
        self._model = WhisperModel("small", device="cpu", compute_type="int8")
        self._window = np.array([], dtype=np.int16)
        self._prev_text = ""

    def transcribe(self, pcm_bytes: bytes) -> str:
        chunk = np.frombuffer(pcm_bytes, dtype=np.int16)
        self._window = np.concatenate([self._window, chunk])
        if len(self._window) > _WINDOW_SAMPLES:
            self._window = self._window[-_WINDOW_SAMPLES:]

        audio = self._window.astype(np.float32) / 32768.0
        segments, _ = self._model.transcribe(
            audio,
            language="ko",
            beam_size=5,
            vad_filter=True,
            vad_parameters={"min_silence_duration_ms": 300, "speech_pad_ms": 100},
        )
        full_text = "".join(seg.text for seg in segments).strip()
        if not full_text:
            return ""
        return self._postprocess(full_text)

    def _postprocess(self, text: str) -> str:
        if text.startswith(self._prev_text):
            new_part = text[len(self._prev_text):].strip()
        else:
            new_part = text.strip()
        self._prev_text = text
        return new_part

    def reset(self):
        self._window = np.array([], dtype=np.int16)
        self._prev_text = ""
