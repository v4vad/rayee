"""
Helper functions and data models for the Rayee API server.

Contains all Pydantic models for request/response validation,
plus helper functions for audio processing and transcription.
"""

import asyncio
import os
from typing import Optional

import numpy as np
from fastapi import HTTPException
from pydantic import BaseModel
from scipy.io import wavfile

from .state import StartupState, state_manager

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


# ============ Helper Functions ============


def raise_models_not_ready():
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


def read_wav_file(audio_path: str) -> np.ndarray:
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


async def transcribe_audio(audio_data: np.ndarray, executor) -> str:
    """Transcribe audio data using the loaded model.

    Args:
        audio_data: The audio to transcribe as a numpy array.
        executor: Which thread pool to run in (audio_executor or upload_executor).
    """
    vocab_prompt = state_manager.vocabulary.get_prompt()
    transcriber = state_manager.get_transcriber()

    def do_transcribe():
        with state_manager.transcription_lock:
            return transcriber.transcribe(
                audio_data, initial_prompt=vocab_prompt if vocab_prompt else None
            )

    loop = asyncio.get_running_loop()
    text = await loop.run_in_executor(executor, do_transcribe)

    return text
