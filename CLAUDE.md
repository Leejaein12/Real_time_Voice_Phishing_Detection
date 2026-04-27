# 보이스피싱 실시간 탐지 앱

## 프로젝트 개요
통화 중 음성을 실시간 분석해 보이스피싱 위험도를 탐지하는 Android 앱.
Python(AI 파이프라인) + Kotlin(Android 앱) 구성.

## AI 파이프라인 구조
```
통화 음성 (실시간)
  ↓ Android SpeechRecognizer (STT)
텍스트
  ↓ 슬라이딩 윈도우 (키워드 1차 필터, <10ms, 창 크기 20단어)
  ↓ 31점 이상이면
KoELECTRA TFLite (문맥 판단, ~80ms, 온디바이스)
  ↓ 위험 판정이면
위험도 % 출력 + 경고
```

> ⚠️ LLM은 학습 데이터 라벨링 단계에서만 사용. 배포 앱에서는 동작하지 않음.
> ⚠️ 최종 배포 모델은 KoELECTRA TFLite. KoBERT는 초기 후보였으나 대체됨.

## 확정된 기술 스택

### Python (AI 파이프라인)
- Python 3.11 / uv 환경
- STT 전처리 (학습용): OpenAI Whisper small
- 형태소 분석: KoNLPy (Okt)
- 1차 필터: 슬라이딩 윈도우 (키워드 빈도 기반)
- 문맥 판단 모델: KoELECTRA (monologg/koelectra-base-v3-discriminator)
- 학습 프레임워크: PyTorch + HuggingFace Transformers
- 경량화: ONNX → TFLite 변환 (목표 크기 20MB 이하)

### Android 앱 (Kotlin)
- Kotlin + Jetpack Compose
- 음성 인식: Android SpeechRecognizer API (실시간)
- AI 추론: TFLite Interpreter (KoELECTRA TFLite, 온디바이스)
- 알림: FCM (Firebase, 가족 알림 서비스)
- 최소 SDK: Android 8.0 (API 26)

## 학습 데이터 구성 (최종)

### 데이터 출처
- 금융감독원 보이스피싱 MP4 104개 → Whisper STT → 키워드 기반 라벨링
- GPT-4o-mini 증강 데이터 (기관사칭 / 금전요구 / 개인정보)
- AI Hub 텍스트 윤리검증 데이터 (정상 클래스)

### 라벨 구조 — 멀티라벨 (확정)
> ⚠️ 기존 5개 단일 클래스(기관사칭/금전요구/개인정보/복합/정상) → 멀티라벨로 변경
> 복합 클래스 제거. 각 카테고리를 독립적으로 판단.

```python
# 라벨 형식: [기관사칭, 금전요구, 개인정보]
[1, 0, 0]  # 기관사칭만
[0, 1, 0]  # 금전요구만
[0, 0, 1]  # 개인정보만
[1, 1, 0]  # 기관사칭 + 금전요구 동시
[1, 0, 1]  # 기관사칭 + 개인정보 동시
[0, 0, 0]  # 정상
```

카테고리별 데이터 분포:
- 기관사칭 포함: 168개
- 금전요구 포함: 128개
- 개인정보 포함: 153개
- 정상 (전부 0): 164개

### 모델 출력 구조
```python
# 손실함수: BCEWithLogitsLoss (멀티라벨용)
# 출력: 3개 노드 (각각 Sigmoid)
# 추론 시 임계값: 0.5 이상이면 해당 카테고리 감지
output = sigmoid(logits)  # [0.92, 0.88, 0.05]
# → 기관사칭: 92%, 금전요구: 88%, 개인정보: 5%
# → 위험도 = max(output) 또는 가중 평균
```

### 데이터 파일 (최종)
- multilabel_all.json: 564개 (전체)
- train_ml.json: 451개
- val_ml.json:    56개
- test_ml.json:   57개

### 라벨링 방식
1. 기관사칭/금전요구/개인정보/정상 → 규칙 기반 직접 변환
2. 복합 → GPT-4o-mini로 [기관사칭, 금전요구, 개인정보] 조합 판단

## 핵심 기능
1. 통화 중 음성 실시간 STT 변환
2. AI 기반 문맥 분석 → 보이스피싱 위험도 (0~100%)
3. 위험도에 따라 버튼 테두리 초록→노랑→빨강 변화 + 글로우 효과
4. 기관사칭 / 금전요구 / 개인정보 카테고리별 감지
5. AI 음성(딥페이크) 탐지
6. 가족 알림 서비스 (위험도 61%+ 시 FCM 푸시)
7. 전화 자동 감지 및 앱 자동 실행

## UI (확정)
- 메인 화면 중앙 원형 대형 버튼 (지름 168dp+)
- 버튼 중앙에 위험도 % 실시간 표시
- 하단에 기관사칭 / 금전요구 / 개인정보 카테고리별 감지 횟수
- 위험도 임계값: 0~30% 안전 / 31~60% 주의 / 61%+ 위험
- 고령자 접근성: 최소 글자 크기 16sp, 진동 경고

## 성능 목표
- 슬라이딩 윈도우: 10ms 이하
- KoELECTRA TFLite 추론: 80ms 이하
- 모델 파일 크기: 20MB 이하 (TFLite 변환 후)
- F1-Score: 87% 이상
- 오탐률: 10% 이하

## 핵심 제약사항
- 음성 데이터 외부 서버 전송 금지 (온디바이스, 가족 알림 제외)
- 통화 음성 디바이스 저장 금지
- Android 8.0 (API 26) 이상 지원
- 통화 캡처: 스피커폰 방식 (MVP), 추후 접근성 서비스 검토
- 가족 알림: Firebase 백엔드 필요 (FCM)
- 서버: 가족 알림용 최소 백엔드만 (나머지 완전 온디바이스)

## 개발 환경
- Python 3.11 / uv
- Docker (Dockerfile, docker-compose.yml, requirements.txt 구성 완료)
- VSCode + Claude Code

## Docker 환경
```bash
docker build -t vp-detector .
docker-compose up -d
docker exec -it vp-detector bash
```

requirements.txt 핵심 버전:
- numpy>=2.0
- onnx==1.15.0
- protobuf<6.0dev,>=5.26.1
- onnx2tf
- tensorflow

## TFLite 변환 현황
- model_float32.tflite: 430MB (추론 동작 확인됨)
- model_float16.tflite: 215MB (CPU ADD 미지원)
- model_int8.tflite: 미완성 (Docker 환경에서 재시도 필요)
- 목표: int8 양자화로 50~100MB 이하

## 미사용 데이터 (2차 목표용)
- 감정분류 대화 음성 데이터 (14GB, AI Hub)
  → 용도: 이상탐지 AutoEncoder 정상 패턴 학습용
  → 사용 시점: 2차 목표 이상탐지 추가 시
  → 처리 방법: Whisper small로 텍스트 변환 후 사용

## 다음 작업 순서
1. train.py — KoELECTRA 멀티라벨 파인튜닝 (BCEWithLogitsLoss)
2. evaluate.py — 카테고리별 F1-Score 확인
3. convert.py — TFLite int8 변환 (Docker 환경)
4. Android 앱 개발 (Kotlin + Jetpack Compose)
5. 슬라이딩 윈도우 Kotlin 코드
6. TFLite 연동 + 전체 테스트
