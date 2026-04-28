import time
from analyzer import analyze
from server.app.models.stt import STTModel


def on_transcribed(text: str):
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{timestamp}] {text}")

    result = analyze(text)
    print(f"위험도:{result['danger_level']:.1%}|{result['categories']}")


if __name__ == "__main__":
    stt = STTModel(device="cpu")
    stt.start(on_transcribed)

    print("STT 시작 — 종료하려면 Ctrl+C")
    try:
        while True:
            time.sleep(0.1)
    except KeyboardInterrupt:
        stt.stop()