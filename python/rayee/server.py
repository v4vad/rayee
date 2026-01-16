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
import threading

from .vad import SmartRecorder
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


# Request/Response models (defines the shape of data we accept/return)

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
async def transcribe():
    """
    Record audio and transcribe it to text.

    This endpoint:
    1. Starts recording from your microphone
    2. Waits for you to speak
    3. Automatically stops when you finish speaking (after ~1.5s of silence)
    4. Transcribes the audio to text using AI
    5. Returns the text

    Returns:
        {"text": "what you said", "status": "success"}

    Errors:
        409: Server is already recording or transcribing
    """
    # Try to start recording
    if not _set_state(ServerState.RECORDING):
        raise HTTPException(
            status_code=409,
            detail=f"Server is busy ({_state.value}). Please wait."
        )

    try:
        # Record with automatic silence detection
        recorder = SmartRecorder(
            silence_duration=1.5,  # Stop after 1.5s of silence
            max_duration=60.0,     # Maximum 60 seconds
        )
        audio_data = recorder.record()

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

        # Transcribe the audio
        transcriber = _get_transcriber()
        text = transcriber.transcribe(
            audio_data,
            initial_prompt=vocab_prompt if vocab_prompt else None
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


# Startup message
@app.on_event("startup")
async def startup_message():
    """Print startup message."""
    print(f"\n{'='*50}")
    print("  Rayee Transcription Server Started")
    print(f"  Running on http://{HOST}:{PORT}")
    print(f"{'='*50}")
    print("\nEndpoints:")
    print("  GET  /status       - Server status")
    print("  POST /transcribe   - Record and transcribe")
    print("  GET  /models       - List available models")
    print("  POST /model        - Switch model")
    print("  GET  /vocabulary   - List custom words")
    print("  POST /vocabulary   - Add custom word")
    print("  DELETE /vocabulary/{word} - Remove word")
    print("\nReady for requests!\n")


def run_server(host: str = HOST, port: int = PORT):
    """
    Start the server.

    Args:
        host: Host to bind to (default: 127.0.0.1)
        port: Port to listen on (default: 8765)
    """
    import uvicorn
    uvicorn.run(app, host=host, port=port)
