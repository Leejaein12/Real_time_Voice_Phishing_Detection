import os
import random
import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import Dataset
import soundfile as sf
import librosa

FIXED_LEN  = 64600  # 16kHz 기준 약 4초
PHONE_SR   = 8000
ORIGIN_SR  = 16000


def _collect_wavs(root_dir):
    paths = []
    for dirpath, _, filenames in os.walk(root_dir):
        for f in filenames:
            if f.lower().endswith('.wav'):
                paths.append(os.path.join(dirpath, f))
    return paths


def _phone_channel(wav: torch.Tensor) -> torch.Tensor:
    wav = wav.unsqueeze(0)
    down = F.interpolate(wav, scale_factor=PHONE_SR / ORIGIN_SR, mode='linear', align_corners=False)
    up   = F.interpolate(down, size=wav.shape[-1], mode='linear', align_corners=False)
    return up.squeeze(0)


def _augment(wav: torch.Tensor) -> torch.Tensor:
    # 1. speed perturbation ±5% — librosa로 pitch 유지하며 속도만 변환
    if random.random() < 0.2:
        factor  = random.uniform(0.95, 1.05)
        wav_np  = wav.squeeze(0).numpy()
        wav_np  = librosa.effects.time_stretch(wav_np, rate=factor)
        if len(wav_np) > FIXED_LEN:
            wav_np = wav_np[:FIXED_LEN]
        else:
            wav_np = np.pad(wav_np, (0, FIXED_LEN - len(wav_np)))
        wav = torch.FloatTensor(wav_np).unsqueeze(0)

    # 2. volume (80%)
    if random.random() < 0.8:
        wav = wav * random.uniform(0.7, 1.3)

    # 3. phone channel (50%) — 전화 통화가 주 타겟
    if random.random() < 0.5:
        wav = _phone_channel(wav)

    # 4. background noise (30%)
    if random.random() < 0.3:
        snr_db     = random.uniform(15, 30)
        signal_rms = wav.pow(2).mean().sqrt().clamp(min=1e-8)
        noise_rms  = signal_rms / (10 ** (snr_db / 20))
        wav        = wav + torch.randn_like(wav) * noise_rms

    return wav.clamp(-1.0, 1.0)


class KoreanDeepVoiceDataset(Dataset):
    def __init__(self, genuine_dir, fake_dir, max_samples=None, seed=42,
                 is_train=True, samples=None):
        """
        genuine_dir : 진짜 한국어 음성 루트
        fake_dir    : 가짜 한국어 음성 루트
        max_samples : 클래스당 최대 샘플 수 (None 이면 전체)
        is_train    : True → augmentation 적용 / False → 클린 로드만 (dev 전용)
        samples     : 외부에서 미리 분리한 [(path, label), ...] 리스트
        """
        self.is_train = is_train

        if samples is not None:
            self.samples = samples
            print(f'[KoreanDataset] pre-split | total={len(self.samples)} | is_train={is_train}')
            return

        real_calls_dir = os.path.join(genuine_dir, 'real_calls')
        news_dir       = os.path.join(genuine_dir, 'news')
        real_calls = _collect_wavs(real_calls_dir) if os.path.exists(real_calls_dir) else []
        news       = _collect_wavs(news_dir)       if os.path.exists(news_dir)       else []
        guaranteed    = real_calls + news
        other_genuine = [p for p in _collect_wavs(genuine_dir) if p not in set(guaranteed)]
        fake_paths    = _collect_wavs(fake_dir)

        random.seed(seed)
        random.shuffle(other_genuine)
        random.shuffle(fake_paths)

        if max_samples is not None:
            fill          = max_samples - len(guaranteed)
            other_genuine = other_genuine[:max(fill, 0)]
            fake_paths    = fake_paths[:max_samples]

        genuine_paths = guaranteed + other_genuine

        self.samples = (
            [(p, 0) for p in genuine_paths] +
            [(p, 1) for p in fake_paths]
        )
        random.shuffle(self.samples)

        print(f'[KoreanDataset] genuine={len(genuine_paths)}, fake={len(fake_paths)}, total={len(self.samples)}')

    def _load_wav(self, path):
        wav, sr = sf.read(path, dtype='float32')
        if wav.ndim == 2:
            wav = wav.mean(axis=1)
        if sr != ORIGIN_SR:
            wav = librosa.resample(wav, orig_sr=sr, target_sr=ORIGIN_SR)
        if len(wav) >= FIXED_LEN:
            wav = wav[:FIXED_LEN]
        else:
            wav = np.pad(wav, (0, FIXED_LEN - len(wav)))
        return torch.FloatTensor(wav).unsqueeze(0)  # (1, T)

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, label = self.samples[idx]
        wav = self._load_wav(path)
        if self.is_train:
            wav = _augment(wav)
        return wav, label
