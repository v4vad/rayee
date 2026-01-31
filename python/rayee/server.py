"""
Rayee API Server

A local web server that the Swift app communicates with.
Handles recording, transcription, model switching, and vocabulary.

All communication happens over HTTP on localhost:8765 - only your Mac can access it.
"""

import asyncio
import os
from typing import Optional

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from scipy.io import wavfile

from .models import AVAILABLE_MODELS, DEFAULT_MODEL
from .startup import audio_executor, on_shutdown, on_startup
from .state import ServerState, StartupState, state_manager
from .transcribe import Transcriber
from .vad import SmartRecorder

# ============ Request/Response Models ============


class TranscribeRequest(BaseModel):
    """Optional parameters for the /transcribe endpoint."""

    silence_duration: float = 1.5


class TranscribeFileRequest(BaseModel):
    """Request for the /transcribe_file endpoint."""

    audio_path: str


class TranscribeResponse(BaseModel):
    """Response from the /transcribe endpoint."""

    text: str
    status: str


class StatusResponse(BaseModel):
    """Response from the /status endpoint."""

    status: str


class ModelRequest(BaseModel):
    """Request to switch models."""

    model: str


class ModelResponse(BaseModel):
    """Response from model-related endpoints."""

    current_model: str
    available_models: list


class VocabularyRequest(BaseModel):
    """Request to add a vocabulary word."""

    word: str


class VocabularyResponse(BaseModel):
    """Response from vocabulary endpoints."""

    words: list
    count: int


class StartupStatusResponse(BaseModel):
    """Response from the /startup_status endpoint."""

    state: str
    message: str
    error: Optional[str] = None


# ============ FastAPI App ============

app = FastAPI(
    title="Rayee Transcription Server",
    description="Local voice-to-text API for the Rayee macOS app",
    version="0.1.0",
)

# Register startup/shutdown handlers
app.add_event_handler("startup", on_startup)
app.add_event_handler("shutdown", on_shutdown)


# ============ Health & Status Endpoints ============


@app.get("/health")
async def health_check():
    """Simple health check endpoint."""
    return {"status": "ok", "service": "rayee"}


@app.get("/status", response_model=StatusResponse)
async def get_status():
    """Get the current server status (idle/recording/transcribing)."""
    return StatusResponse(status=state_manager.state.value)


@app.get("/startup_status", response_model=StartupStatusResponse)
async def get_startup_status():
    """Get the current startup/model loading status."""
    return StartupStatusResponse(
        state=state_manager.startup_state.value,
        message=state_manager.startup_message,
        error=state_manager.startup_error,
    )


# ============ Transcription Endpoints ============


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(request: TranscribeRequest = TranscribeRequest()):
    """
    Record audio and transcribe it to text.

    Starts recording, waits for speech, stops when silence detected,
    then transcribes using AI.
    """
    # Check if models are ready
    if not state_manager.models_ready:
        _raise_models_not_ready()

    # Try to start recording
    if not state_manager.set_state(ServerState.RECORDING):
        raise HTTPException(
            status_code=409,
            detail=f"Server is busy ({state_manager.state.value}). Please wait.",
        )

    try:
        # Record with automatic silence detection
        recorder = SmartRecorder(
            silence_duration=request.silence_duration,
            max_duration=60.0,
        )
        loop = asyncio.get_running_loop()
        audio_data = await loop.run_in_executor(audio_executor, recorder.record)

        # Check if we got any audio
        if len(audio_data) == 0:
            state_manager.set_state(ServerState.IDLE)
            return TranscribeResponse(text="", status="no_speech_detected")

        # Transcribe
        state_manager.set_state(ServerState.TRANSCRIBING)
        text = await _transcribe_audio(audio_data)

        return TranscribeResponse(text=text, status="success")

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

    finally:
        state_manager.set_state(ServerState.IDLE)


@app.post("/transcribe_file", response_model=TranscribeResponse)
async def transcribe_file(request: TranscribeFileRequest):
    """
    Transcribe audio from a WAV file.

    Used when Swift app records audio directly (solves macOS permission issues).
    File must be: WAV, 16kHz, mono, float32 or int16.
    """
    # Check if models are ready
    if not state_manager.models_ready:
        _raise_models_not_ready()

    # Validate file exists
    if not os.path.exists(request.audio_path):
        raise HTTPException(
            status_code=400, detail=f"Audio file not found: {request.audio_path}"
        )

    # Try to enter transcribing state
    if not state_manager.set_state(ServerState.TRANSCRIBING):
        raise HTTPException(
            status_code=409,
            detail=f"Server is busy ({state_manager.state.value}). Please wait.",
        )

    try:
        # Read and validate the WAV file
        audio_data = _read_wav_file(request.audio_path)

        if len(audio_data) == 0:
            return TranscribeResponse(text="", status="no_audio")

        # Transcribe
        text = await _transcribe_audio(audio_data)

        return TranscribeResponse(text=text, status="success")

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

    finally:
        state_manager.set_state(ServerState.IDLE)


# ============ Model Endpoints ============


@app.get("/models", response_model=ModelResponse)
async def list_models():
    """List available AI models and which one is currently active."""
    transcriber = state_manager.get_transcriber()
    current = transcriber.get_model_info()

    models_list = []
    for name, info in AVAILABLE_MODELS.items():
        models_list.append(
            {
                "name": name,
                "description": info["description"],
                "size_mb": info["size_mb"],
                "is_current": name == current.get("model_size"),
                "is_loaded": current.get("is_loaded", False)
                and name == current.get("model_size"),
            }
        )

    return ModelResponse(
        current_model=current.get("model_size", DEFAULT_MODEL),
        available_models=models_list,
    )


@app.post("/model")
async def switch_model(request: ModelRequest):
    """Switch to a different AI model."""
    if state_manager.state != ServerState.IDLE:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot switch model while {state_manager.state.value}",
        )

    if request.model not in AVAILABLE_MODELS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown model: {request.model}. Available: {list(AVAILABLE_MODELS.keys())}",
        )

    # Create new transcriber with the requested model
    state_manager.set_transcriber(Transcriber(model_size=request.model))

    return {
        "current_model": request.model,
        "message": f"Model switched to '{request.model}'. Will be loaded on next transcription.",
    }


# ============ Vocabulary Endpoints ============


@app.get("/vocabulary", response_model=VocabularyResponse)
async def get_vocabulary():
    """List all custom vocabulary words."""
    return VocabularyResponse(
        words=state_manager.vocabulary.get_words(),
        count=state_manager.vocabulary.count(),
    )


@app.post("/vocabulary", response_model=VocabularyResponse)
async def add_vocabulary_word(request: VocabularyRequest):
    """Add a custom word to the vocabulary."""
    word = request.word.strip()
    if not word:
        raise HTTPException(status_code=400, detail="Word cannot be empty")

    state_manager.vocabulary.add_word(word)

    return VocabularyResponse(
        words=state_manager.vocabulary.get_words(),
        count=state_manager.vocabulary.count(),
    )


@app.delete("/vocabulary/{word}")
async def remove_vocabulary_word(word: str):
    """Remove a word from the vocabulary."""
    removed = state_manager.vocabulary.remove_word(word)

    return {
        "words": state_manager.vocabulary.get_words(),
        "count": state_manager.vocabulary.count(),
        "removed": removed,
    }


# ============ Helper Functions ============


def _raise_models_not_ready():
    """Raise appropriate error when models aren't loaded yet."""
    if state_manager.startup_state == StartupState.FAILED:
        raise HTTPException(
            status_code=503,
            detail=f"Model loading failed: {state_manager.startup_error}",
        )
    else:
        raise HTTPException(
            status_code=503,
            detail=f"Models are still loading ({state_manager.startup_state.value}). Please wait.",
        )


def _read_wav_file(audio_path: str) -> np.ndarray:
    """Read and validate a WAV file, returning normalized float32 audio."""
    try:
        sample_rate, audio_data = wavfile.read(audio_path)
    except Exception as e:
        raise HTTPException(
            status_code=400, detail=f"Failed to read WAV file: {str(e)}"
        )

    # Validate sample rate (Whisper expects 16kHz)
    if sample_rate != 16000:
        raise HTTPException(
            status_code=400, detail=f"Expected 16kHz sample rate, got {sample_rate}Hz"
        )

    # Convert to float32 if needed
    if audio_data.dtype == np.int16:
        audio_data = audio_data.astype(np.float32) / 32768.0
    elif audio_data.dtype == np.int32:
        audio_data = audio_data.astype(np.float32) / 2147483648.0
    elif audio_data.dtype != np.float32:
        audio_data = audio_data.astype(np.float32)

    # Ensure mono (take first channel if stereo)
    if len(audio_data.shape) > 1:
        audio_data = audio_data[:, 0]

    return audio_data


async def _transcribe_audio(audio_data: np.ndarray) -> str:
    """Transcribe audio data using the loaded model."""
    vocab_prompt = state_manager.vocabulary.get_prompt()
    transcriber = state_manager.get_transcriber()

    loop = asyncio.get_running_loop()
    text = await loop.run_in_executor(
        audio_executor,
        lambda: transcriber.transcribe(
            audio_data, initial_prompt=vocab_prompt if vocab_prompt else None
        ),
    )

    return text
