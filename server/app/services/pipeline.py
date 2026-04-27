import concurrent.futures

from app.core.config import settings
from app.core.schemas import PipelineResult
from app.models.deepfake import DeepfakeModel
from app.models.nlu import NLUModel
from app.models.stt import STTModel
from app.services.audio_processor import convert_to_pcm
from app.services.explainer import explain

_executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)

# RawNet2 입력 크기: 64,600 samples * 2 bytes (PCM 16-bit)
_DEEPFAKE_BUFFER_BYTES = 64600 * 2


class Pipeline:
    def __init__(self):
        self.stt = STTModel()
        self.deepfake = DeepfakeModel()
        self.nlu = NLUModel()
        self._deepfake_buffer = bytearray()
        self._deepfake_result = {"is_fake": False, "confidence": 0.0}

    def process(self, audio_chunk: bytes) -> dict:
        pcm_chunk = convert_to_pcm(audio_chunk)

        # STT는 매 청크마다 처리
        stt_future = _executor.submit(self.stt.transcribe, pcm_chunk)

        # Deepfake는 4초(64,600 샘플)가 쌓이면 처리, 그 전엔 이전 결과 재사용
        self._deepfake_buffer.extend(pcm_chunk)
        if len(self._deepfake_buffer) >= _DEEPFAKE_BUFFER_BYTES:
            deepfake_input = bytes(self._deepfake_buffer[:_DEEPFAKE_BUFFER_BYTES])
            self._deepfake_buffer = self._deepfake_buffer[_DEEPFAKE_BUFFER_BYTES:]
            deepfake_future = _executor.submit(self.deepfake.predict, deepfake_input)
        else:
            deepfake_future = None

        text = stt_future.result()
        if deepfake_future is not None:
            self._deepfake_result = deepfake_future.result()
        deepfake_result = self._deepfake_result

        # NLU 위험 점수
        nlu_result = self.nlu.analyze(text)
        risk_score = nlu_result["risk_score"]
        warning_level = 3 if deepfake_result["is_fake"] else self._get_warning_level(risk_score)

        if warning_level >= 1 or deepfake_result["is_fake"]:
            llm_explanation = explain(
                transcript=text,
                risk_score=risk_score,
                is_fake_voice=deepfake_result["is_fake"],
                warning_level=warning_level,
            )
        else:
            llm_explanation = "정상적인 통화로 보입니다."

        return PipelineResult(
            text=text,
            risk_score=risk_score,
            warning_level=warning_level,
            is_fake_voice=deepfake_result["is_fake"],
            deepfake_confidence=deepfake_result["confidence"],
            explanation=llm_explanation,
        ).model_dump()

    def _get_warning_level(self, score: int) -> int:
        if score < settings.threshold_low:
            return 0
        elif score < settings.threshold_mid:
            return 1
        elif score < settings.threshold_high:
            return 2
        return 3
