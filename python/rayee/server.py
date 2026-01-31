"""
Rayee API Server

A local web server that the Swift app communicates with.
Handles recording, transcription, model switching, and vocabulary.

All communication happens over HTTP on localhost:8765 - only your Mac can access it.
"""

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from typing import Optional, Literal
from enum import Enum
import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor
import os
import numpy as np
from scipy.io import wavfile

from .vad import SmartRecorder, VoiceActivityDetector
from .transcribe import Transcriber
from .models import AVAILABLE_MODELS, DEFAULT_MODEL, ModelSize
from .vocabulary import VocabularyManager


# Server configuration
HOST = "127.0.0.1"  # localhost only - secure
PORT = 8765


# Server state - tracks what the server is currently doing
class ServerState(str, Enum):
    IDLE = "idle"               # Ready for a new command
    RECORDING = "recording"      # Microphone active, listening
    TRANSCRIBING = "transcribing"  # Processing audio to text


# Startup state - tracks model download progress
class StartupState(str, Enum):
    NOT_STARTED = "not_started"           # Haven't started yet
    DOWNLOADING_VAD = "downloading_vad"    # Downloading voice detection model
    DOWNLOADING_WHISPER = "downloading_whisper"  # Downloading transcription model
    READY = "ready"                        # All models loaded, ready to transcribe
    FAILED = "failed"                      # Something went wrong during startup


# Request/Response models (defines the shape of data we accept/return)

class TranscribeRequest(BaseModel):
    """Optional parameters for the /transcribe endpoint."""
    silence_duration: float = 1.5  # How long to wait after speech stops (seconds)


class TranscribeFileRequest(BaseModel):
    """Request for the /transcribe_file endpoint."""
    audio_path: str  # Path to the WAV file to transcribe


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


class ErrorResponse(BaseModel):
    """Error response format."""
    error: str
    detail: Optional[str] = None


class StartupStatusResponse(BaseModel):
    """Response from the /startup_status endpoint."""
    state: str  # not_started, downloading_vad, downloading_whisper, ready, failed
    message: str  # Human-readable status message
    error: Optional[str] = None  # Error message if failed


# Create the FastAPI app
app = FastAPI(
    title="Rayee Transcription Server",
    description="Local voice-to-text API for the Rayee macOS app",
    version="0.1.0"
)


# Global state
_state = ServerState.IDLE
_state_lock = threading.Lock()  # Prevents race conditions
_transcriber: Optional[Transcriber] = None
_vocabulary = VocabularyManager()

# Startup state for model downloads
_startup_state = StartupState.NOT_STARTED
_startup_message = "Server starting..."
_startup_error: Optional[str] = None
_models_ready = False  # True once both models are loaded

# Dedicated executor for audio/transcription work
# Using a single worker ensures audio operations don't compete for resources
# and helps with macOS audio thread requirements
_audio_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="rayee_audio")


def _get_transcriber() -> Transcriber:
    """Get or create the transcriber instance."""
    global _transcriber
    if _transcriber is None:
        _transcriber = Transcriber()
    return _transcriber


def _set_state(new_state: ServerState) -> bool:
    """
    Try to change the server state.

    Returns True if state was changed, False if transition not allowed.
    Only allows transitioning FROM idle state (except when going back to idle).
    """
    global _state
    with _state_lock:
        # Always allow transitioning back to idle
        if new_state == ServerState.IDLE:
            _state = new_state
            return True

        # Only allow starting new operations from idle
        if _state != ServerState.IDLE:
            return False

        _state = new_state
        return True


# ============ API Endpoints ============


@app.get("/status", response_model=StatusResponse)
async def get_status():
    """
    Get the current server status.

    Returns:
        {"status": "idle" | "recording" | "transcribing"}
    """
    return StatusResponse(status=_state.value)


@app.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(request: TranscribeRequest = TranscribeRequest()):
    """
    Record audio and transcribe it to text.

    This endpoint:
    1. Starts recording from your microphone
    2. Waits for you to speak
    3. Automatically stops when you finish speaking (based on silence_duration)
    4. Transcribes the audio to text using AI
    5. Returns the text

    Args:
        request: Optional settings including silence_duration (default 1.5s)

    Returns:
        {"text": "what you said", "status": "success"}

    Errors:
        409: Server is already recording or transcribing
        503: Models are still loading
    """
    # Check if models are ready
    if not _models_ready:
        if _startup_state == StartupState.FAILED:
            raise HTTPException(
                status_code=503,
                detail=f"Model loading failed: {_startup_error}"
            )
        else:
            raise HTTPException(
                status_code=503,
                detail=f"Models are still loading ({_startup_state.value}). Please wait."
            )

    # Try to start recording
    if not _set_state(ServerState.RECORDING):
        raise HTTPException(
            status_code=409,
            detail=f"Server is busy ({_state.value}). Please wait."
        )

    try:
        # Record with automatic silence detection
        # silence_duration comes from the user's settings (how long to wait after speech stops)
        recorder = SmartRecorder(
            silence_duration=request.silence_duration,
            max_duration=60.0,     # Maximum 60 seconds
        )
        # Run recording in a dedicated thread so the server can still respond
        # to health checks while waiting for the user to speak
        # We use a dedicated executor (not the default thread pool) for better
        # compatibility with macOS audio requirements
        loop = asyncio.get_running_loop()
        audio_data = await loop.run_in_executor(_audio_executor, recorder.record)

        # Check if we got any audio
        if len(audio_data) == 0:
            _set_state(ServerState.IDLE)
            return TranscribeResponse(
                text="",
                status="no_speech_detected"
            )

        # Switch to transcribing state
        _set_state(ServerState.TRANSCRIBING)

        # Get vocabulary prompt for better recognition of custom words
        vocab_prompt = _vocabulary.get_prompt()

        # Transcribe the audio (also in the dedicated thread to keep server responsive)
        transcriber = _get_transcriber()
        text = await loop.run_in_executor(
            _audio_executor,
            lambda: transcriber.transcribe(audio_data, initial_prompt=vocab_prompt if vocab_prompt else None)
        )

        return TranscribeResponse(
            text=text,
            status="success"
        )

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Transcription failed: {str(e)}"
        )

    finally:
        # Always go back to idle
        _set_state(ServerState.IDLE)


@app.post("/transcribe_file", response_model=TranscribeResponse)
async def transcribe_file(request: TranscribeFileRequest):
    """
    Transcribe audio from a WAV file.

    This endpoint is used when the Swift app records audio directly
    (instead of the Python server recording). This solves the macOS
    microphone permission issue when running as a bundled app.

    The audio file must be:
    - WAV format
    - 16kHz sample rate
    - Mono (1 channel)
    - Float32 or Int16 samples

    Args:
        request: Contains audio_path - path to the WAV file

    Returns:
        {"text": "transcribed text", "status": "success"}

    Errors:
        400: File not found or invalid format
        409: Server is already transcribing
        503: Models are still loading
    """
    # Check if models are ready
    if not _models_ready:
        if _startup_state == StartupState.FAILED:
            raise HTTPException(
                status_code=503,
                detail=f"Model loading failed: {_startup_error}"
            )
        else:
            raise HTTPException(
                status_code=503,
                detail=f"Models are still loading ({_startup_state.value}). Please wait."
            )

    # Validate file exists
    audio_path = request.audio_path
    if not os.path.exists(audio_path):
        raise HTTPException(
            status_code=400,
            detail=f"Audio file not found: {audio_path}"
        )

    # Try to enter transcribing state
    if not _set_state(ServerState.TRANSCRIBING):
        raise HTTPException(
            status_code=409,
            detail=f"Server is busy ({_state.value}). Please wait."
        )

    try:
        # Read the WAV file
        try:
            sample_rate, audio_data = wavfile.read(audio_path)
        except Exception as e:
            raise HTTPException(
                status_code=400,
                detail=f"Failed to read WAV file: {str(e)}"
            )

        # Validate sample rate (Whisper expects 16kHz)
        if sample_rate != 16000:
            raise HTTPException(
                status_code=400,
                detail=f"Expected 16kHz sample rate, got {sample_rate}Hz"
            )

        # Convert to float32 if needed (Whisper expects float32 in range -1 to 1)
        if audio_data.dtype == np.int16:
            audio_data = audio_data.astype(np.float32) / 32768.0
        elif audio_data.dtype == np.int32:
            audio_data = audio_data.astype(np.float32) / 2147483648.0
        elif audio_data.dtype != np.float32:
            audio_data = audio_data.astype(np.float32)

        # Ensure mono (take first channel if stereo)
        if len(audio_data.shape) > 1:
            audio_data = audio_data[:, 0]

        # Check if we got any audio
        if len(audio_data) == 0:
            return TranscribeResponse(
                text="",
                status="no_audio"
            )

        # Get vocabulary prompt for better recognition of custom words
        vocab_prompt = _vocabulary.get_prompt()

        # Transcribe the audio
        loop = asyncio.get_running_loop()
        transcriber = _get_transcriber()
        text = await loop.run_in_executor(
            _audio_executor,
            lambda: transcriber.transcribe(audio_data, initial_prompt=vocab_prompt if vocab_prompt else None)
        )

        return TranscribeResponse(
            text=text,
            status="success"
        )

    except HTTPException:
        raise  # Re-raise HTTP exceptions as-is

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Transcription failed: {str(e)}"
        )

    finally:
        # Always go back to idle
        _set_state(ServerState.IDLE)


@app.get("/models", response_model=ModelResponse)
async def list_models():
    """
    List available AI models and which one is currently active.

    Returns:
        {
            "current_model": "small",
            "available_models": [
                {"name": "tiny", "description": "...", "size_mb": 75},
                ...
            ]
        }
    """
    transcriber = _get_transcriber()
    current = transcriber.get_model_info()

    models_list = []
    for name, info in AVAILABLE_MODELS.items():
        models_list.append({
            "name": name,
            "description": info["description"],
            "size_mb": info["size_mb"],
            "is_current": name == current.get("model_size"),
            "is_loaded": current.get("is_loaded", False) and name == current.get("model_size"),
        })

    return ModelResponse(
        current_model=current.get("model_size", DEFAULT_MODEL),
        available_models=models_list
    )


@app.post("/model")
async def switch_model(request: ModelRequest):
    """
    Switch to a different AI model.

    Available models: tiny, base, small, medium, large-v3

    Larger models are more accurate but slower and use more memory.

    Args:
        {"model": "small"}

    Returns:
        {"current_model": "small", "message": "Model switched successfully"}

    Errors:
        400: Invalid model name
        409: Server is busy (recording/transcribing)
    """
    # Don't allow switching while busy
    if _state != ServerState.IDLE:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot switch model while {_state.value}"
        )

    model_name = request.model
    if model_name not in AVAILABLE_MODELS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown model: {model_name}. Available: {list(AVAILABLE_MODELS.keys())}"
        )

    # Load the new model
    global _transcriber
    _transcriber = Transcriber(model_size=model_name)

    return {
        "current_model": model_name,
        "message": f"Model switched to '{model_name}'. Will be loaded on next transcription."
    }


@app.get("/vocabulary", response_model=VocabularyResponse)
async def get_vocabulary():
    """
    List all custom vocabulary words.

    Returns:
        {"words": ["word1", "word2"], "count": 2}
    """
    return VocabularyResponse(
        words=_vocabulary.get_words(),
        count=_vocabulary.count()
    )


@app.post("/vocabulary", response_model=VocabularyResponse)
async def add_vocabulary_word(request: VocabularyRequest):
    """
    Add a custom word to the vocabulary.

    Custom words help the AI recognize names, technical terms, etc.

    Args:
        {"word": "Rayee"}

    Returns:
        {"words": [...], "count": N}
    """
    word = request.word.strip()
    if not word:
        raise HTTPException(status_code=400, detail="Word cannot be empty")

    added = _vocabulary.add_word(word)

    return VocabularyResponse(
        words=_vocabulary.get_words(),
        count=_vocabulary.count()
    )


@app.delete("/vocabulary/{word}")
async def remove_vocabulary_word(word: str):
    """
    Remove a word from the vocabulary.

    Args:
        word: The word to remove (in the URL path)

    Returns:
        {"words": [...], "count": N, "removed": true/false}
    """
    removed = _vocabulary.remove_word(word)

    return {
        "words": _vocabulary.get_words(),
        "count": _vocabulary.count(),
        "removed": removed
    }


@app.get("/health")
async def health_check():
    """Simple health check endpoint."""
    return {"status": "ok", "service": "rayee"}


@app.get("/startup_status", response_model=StartupStatusResponse)
async def get_startup_status():
    """
    Get the current startup/model loading status.

    This endpoint is used by the Swift app during startup to show
    appropriate feedback while AI models are downloading.

    Returns:
        {
            "state": "downloading_vad" | "downloading_whisper" | "ready" | "failed",
            "message": "Human readable status...",
            "error": null | "Error message if failed"
        }
    """
    return StartupStatusResponse(
        state=_startup_state.value,
        message=_startup_message,
        error=_startup_error
    )


# Startup message and model preloading
@app.on_event("startup")
async def startup_message():
    """Print startup message and preload AI models."""
    global _startup_state, _startup_message, _startup_error, _models_ready

    print(f"\n{'='*50}")
    print("  Rayee Transcription Server Started")
    print(f"  Running on http://{HOST}:{PORT}")
    print(f"{'='*50}")
    print("\nEndpoints:")
    print("  GET  /status         - Server status")
    print("  GET  /startup_status - Model loading status")
    print("  POST /transcribe     - Record and transcribe")
    print("  GET  /models         - List available models")
    print("  POST /model          - Switch model")
    print("  GET  /vocabulary     - List custom words")
    print("  POST /vocabulary     - Add custom word")
    print("  DELETE /vocabulary/{word} - Remove word")

    # Pre-load AI models in background so they're ready when user first records
    print("\nPreloading AI models (this may take a few minutes on first run)...")

    def preload_models():
        global _startup_state, _startup_message, _startup_error, _models_ready

        try:
            # Step 1: Load VAD model
            _startup_state = StartupState.DOWNLOADING_VAD
            _startup_message = "Downloading voice detection model..."
            print(f"[Startup] {_startup_message}")

            vad = VoiceActivityDetector()
            vad.load_model()

            # Step 2: Load Whisper model
            _startup_state = StartupState.DOWNLOADING_WHISPER
            _startup_message = "Downloading transcription model..."
            print(f"[Startup] {_startup_message}")

            transcriber = _get_transcriber()
            transcriber.load_model()

            # All done!
            _startup_state = StartupState.READY
            _startup_message = "All models loaded. Ready to transcribe!"
            _models_ready = True
            print(f"[Startup] {_startup_message}")
            print("\nReady for requests!\n")

        except TimeoutError as e:
            _startup_state = StartupState.FAILED
            _startup_message = "Model download timed out"
            _startup_error = str(e)
            print(f"[Startup] ERROR: {e}")

        except Exception as e:
            _startup_state = StartupState.FAILED
            _startup_message = "Failed to load models"
            _startup_error = str(e)
            print(f"[Startup] ERROR: {e}")

    # Run model loading in the audio executor thread
    # This keeps the server responsive while models download
    loop = asyncio.get_running_loop()
    loop.run_in_executor(_audio_executor, preload_models)


@app.on_event("shutdown")
async def shutdown_cleanup():
    """Clean up resources on shutdown."""
    _audio_executor.shutdown(wait=False)
    print("Server shutting down...")


def run_server(host: str = HOST, port: int = PORT):
    """
    Start the server.

    Args:
        host: Host to bind to (default: 127.0.0.1)
        port: Port to listen on (default: 8765)
    """
    import uvicorn
    uvicorn.run(app, host=host, port=port)
