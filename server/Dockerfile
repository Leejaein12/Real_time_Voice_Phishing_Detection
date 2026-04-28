FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

RUN pip install uv

COPY pyproject.toml uv.lock ./
RUN uv export --no-hashes --no-dev -o requirements.txt && \
<<<<<<< HEAD
    pip install --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        -r requirements.txt
=======
    uv pip install --system --no-cache -r requirements.txt
>>>>>>> eea11f0e68a0202ab5d7ae84cfbd5930b79c70da

COPY . .

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
