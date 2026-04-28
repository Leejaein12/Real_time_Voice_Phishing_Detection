import asyncio
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.config import settings
from app.services.pipeline import Pipeline

router = APIRouter()


@router.websocket("/ws/audio")
async def audio_stream(websocket: WebSocket):
    await websocket.accept()
    pipeline = Pipeline()
    audio_buffer = bytearray()
    chunk_bytes = settings.chunk_bytes

    try:
        while True:
            data = await websocket.receive_bytes()
            audio_buffer.extend(data)

            while len(audio_buffer) >= chunk_bytes:
                chunk = bytes(audio_buffer[:chunk_bytes])
                audio_buffer = audio_buffer[chunk_bytes:]

                try:
                    result = await asyncio.to_thread(pipeline.process, chunk)
                    await websocket.send_json(result)
                except Exception as e:
                    await websocket.send_json({"error": str(e)})

    except WebSocketDisconnect:
        pass
