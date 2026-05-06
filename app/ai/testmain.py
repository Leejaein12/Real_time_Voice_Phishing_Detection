#가짜/진짜 구분 테스트메인 코드
import sys 
sys.path.insert(0, '/content/drive/MyDrive/RealTimeVoicePhishing')
import torch, soundfile as sf, numpy as np
from model import RawNet2
from pydub import AudioSegment

FIXED_LEN = 64600
DEVICE = 'cuda' if torch.cuda.is_available() else 'cpu'

model = RawNet2().to(DEVICE)
model.load_state_dict(torch.load('/content/drive/MyDrive/checkpoints/korean_model.pth', map_location=DEVICE))
model.eval()

def convert_to_wav(path):
    if path.endswith('.m4a'):
        wav_path = path.replace('.m4a', '.wav')
        AudioSegment.from_file(path, format='m4a').set_frame_rate(16000).set_channels(1).export(wav_path, format='wav')
        return wav_path
    return path

def predict(wav_path):
    wav_path = convert_to_wav(wav_path)
    wav, sr = sf.read(wav_path, dtype='float32')  # sr도 받기
    if wav.ndim == 2:
        wav = wav.mean(axis=1)
    if sr != 16000:  # ← 이 부분 추가 (학습 전처리와 동일)
        import librosa
        wav = librosa.resample(wav, orig_sr=sr, target_sr=16000)
    if len(wav) >= FIXED_LEN:
        wav = wav[:FIXED_LEN]
    else:
        wav = np.pad(wav, (0, FIXED_LEN - len(wav)))
    t = torch.FloatTensor(wav).unsqueeze(0).unsqueeze(0)
    down = torch.nn.functional.interpolate(t, scale_factor=0.5, mode='linear', align_corners=False)
    t = torch.nn.functional.interpolate(down, size=t.shape[-1], mode='linear', align_corners=False)
    t = t.to(DEVICE)
    with torch.no_grad():
        prob = torch.softmax(model(t), dim=1)[0, 1].item()
    label = '가짜 (AI 목소리)' if prob > 0.5 else '진짜 (사람 목소리)'
    print(f'{label} | 가짜 확률: {prob:.2%}')


predict('/content/drive/MyDrive/sample.wav')
  # 파일명 수정