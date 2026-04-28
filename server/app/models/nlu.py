import sys
import threading
from pathlib import Path

_NLU_PATH = Path(__file__).parent.parent.parent.parent / "NLU"
sys.path.insert(0, str(_NLU_PATH))

try:
    import analyzer as _nlu_analyzer
    _ANALYZER_AVAILABLE = True
except Exception:
    _ANALYZER_AVAILABLE = False

# analyzer는 모듈 전역 변수 사용 — 동시 접속 보호
_lock = threading.Lock()


class NLUModel:
    def __init__(self):
        if _ANALYZER_AVAILABLE:
            with _lock:
                _nlu_analyzer.reset()

    def analyze(self, text: str) -> dict:
        if not text:
            return {"risk_score": 0, "categories": []}

        if _ANALYZER_AVAILABLE:
            try:
                with _lock:
                    result = _nlu_analyzer.analyze(text)
                # KoELECTRA 실행됐으면 그 점수, 아니면 키워드 점수 사용
                if result["triggered"]:
                    risk_score = int(result["danger_level"] * 100)
                else:
                    risk_score = min(result["keyword_score"], 100)
                return {
                    "risk_score": risk_score,
                    "categories": result["categories"],
                }
            except Exception:
                pass

        # KoELECTRA 미설치 시 키워드 점수만 사용
        from pipeline.filter import PHISHING_KEYWORDS, _normalize
        normalized = _normalize(text).lower()
        score = sum(
            10
            for keywords in PHISHING_KEYWORDS.values()
            for kw in keywords
            if kw.lower() in normalized
        )
        return {"risk_score": min(score, 100), "categories": []}
