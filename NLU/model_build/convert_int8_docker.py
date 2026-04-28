"""
ONNX → TFLite 변환 (Docker 전용)
onnx2tf로 float16 TFLite 직접 생성
"""
import os
import shutil
import subprocess
import sys

ONNX_SRC  = "/app/input/model.onnx"
ONNX_TMP  = "/tmp/model.onnx"
OUTPUT_DIR = "/app/output"
OUTPUT    = f"{OUTPUT_DIR}/model_float16.tflite"

print("[1/1] ONNX → TFLite (float16) 변환 중...")

shutil.copy(ONNX_SRC, ONNX_TMP)
data_file = "/app/input/model.onnx.data"
if os.path.exists(data_file):
    shutil.copy(data_file, "/tmp/model.onnx.data")

result = subprocess.run(
    ["onnx2tf", "-i", ONNX_TMP, "-o", OUTPUT_DIR, "-eatfp16"],
    capture_output=True, text=True,
)
print(result.stdout[-3000:] if len(result.stdout) > 3000 else result.stdout)
if result.stderr:
    print("[STDERR]", result.stderr[-1000:])

if not os.path.exists(OUTPUT):
    print(f"변환 실패: {OUTPUT} 없음")
    sys.exit(1)

size_mb = os.path.getsize(OUTPUT) / 1024 / 1024
print(f"\n완료: {OUTPUT}  ({size_mb:.1f} MB)")
