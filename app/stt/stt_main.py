import queue
import threading
import time
from analyzer import analyze
from server.app.models.stt import STTModel

audio_queue = queue.Queue()
stt = STTModel(device="cpu")


def transcribe_audio(stop_event, result_callback):
    while not stop_event.is_set():
        try:
            segment_bytes, enqueue_time = audio_queue.get(timeout=1.0)
        except queue.Empty:
            continue

        while not audio_queue.empty():
            try:
                segment_bytes, enqueue_time = audio_queue.get_nowait()
            except queue.Empty:
                break

        if time.time() - enqueue_time > 2.0:
            stt.reset()
            continue

        result = stt.transcribe(segment_bytes)
        if result:
            result_callback(result)


def on_transcribed(text: str):
    timestamp = time.strftime("%H:%M:%S")
    print(f"[{timestamp}] {text}")
    
    result = analyze(text)
    print(f"위험도:{result['danger_level']:.1%}|{result['categories']}")


if __name__ == "__main__":
    stop_event = threading.Event()
    t_stt = threading.Thread(target=transcribe_audio, args=(stop_event, on_transcribed), daemon=True)
    t_stt.start()

    print("STT 시작 — 종료하려면 Ctrl+C")
    try:
        while True:
            time.sleep(0.1)
    except KeyboardInterrupt:
        stop_event.set()

    t_stt.join(timeout=3)