"""
Rayee API Server

A local web server that the Swift app communicates with.
Handles recording, transcription, model switching, and vocabulary.

All communication happens over a Unix domain socket (~/.rayee/server.sock) - only your Mac can access it.
"""

import asyncio

from fastapi import FastAPI, HTTPException

from .models import (
    AVAILABLE_MODELS,
    DEFAULT_MODEL,
    delete_fw_model,
    download_fw_model,
    get_fw_download_error,
    get_fw_model_status,
)
from .server_helpers import (
    FWActionResponse,
    FWDownloadResponse,
    ModelRequest,
    ModelResponse,
    SettingsResponse,
    SettingsUpdateRequest,
    StartupStatusResponse,
    StatusResponse,
    TranscribeFileRequest,
    TranscribeRequest,
    TranscribeResponse,
    VocabularyRequest,
    VocabularyResponse,
    raise_models_not_ready,
    read_wav_file,
    transcribe_audio,
)
from .startup import (
    audio_executor,
    on_shutdown,
    on_startup,
    transform_executor,
    upload_executor,
)
from .state import ServerState, state_manager
from .transcribe import Transcriber
from .transform_routes import router as transform_router
from .vad import SmartRecorder

# ============ FastAPI App ============

app = FastAPI(
    title="Rayee Transcription Server",
    description="Local voice-to-text API for the Rayee macOS app",
    version="0.1.0",
)

# Register startup/shutdown handlers
app.add_event_handler("startup", on_startup)
app.add_event_handler("shutdown", on_shutdown)

# Include text transformation routes
app.include_router(transform_router)


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
        raise_models_not_ready()

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
        text = await transcribe_audio(audio_data, audio_executor)

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
        raise_models_not_ready()

    # Validate file exists
    import os

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
        # Read and validate the WAV file (off the event loop)
        loop = asyncio.get_running_loop()
        audio_data = await loop.run_in_executor(
            audio_executor, lambda: read_wav_file(request.audio_path)
        )

        if len(audio_data) == 0:
            return TranscribeResponse(text="", status="no_audio")

        # Transcribe
        text = await transcribe_audio(audio_data, audio_executor)

        return TranscribeResponse(text=text, status="success")

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")

    finally:
        state_manager.set_state(ServerState.IDLE)


@app.post("/transcribe_upload", response_model=TranscribeResponse)
async def transcribe_upload(request: TranscribeFileRequest):
    """
    Transcribe an uploaded audio file without blocking recording.

    Unlike /transcribe_file, this does NOT touch the state machine,
    so the hotkey recording flow still works while this runs.
    Uses a separate thread pool (upload_executor) for processing.
    """
    if not state_manager.models_ready:
        raise_models_not_ready()

    import os

    if not os.path.exists(request.audio_path):
        raise HTTPException(
            status_code=400, detail=f"Audio file not found: {request.audio_path}"
        )

    try:
        loop = asyncio.get_running_loop()
        audio_data = await loop.run_in_executor(
            upload_executor, lambda: read_wav_file(request.audio_path)
        )

        if len(audio_data) == 0:
            return TranscribeResponse(text="", status="no_audio")

        text = await transcribe_audio(audio_data, upload_executor)
        return TranscribeResponse(text=text, status="success")

    except HTTPException:
        raise

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(e)}")


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
                "category": info.get("category", "standard"),
                "is_current": name == current.get("model_size"),
                "is_loaded": current.get("is_loaded", False)
                and name == current.get("model_size"),
                "status": get_fw_model_status(name),
                "error": get_fw_download_error(name),
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


# ============ Faster-Whisper Download/Delete Endpoints ============


@app.post("/models/download/{model_name}", response_model=FWDownloadResponse)
async def download_fw_model_endpoint(model_name: str):
    """Start downloading a Faster-Whisper model in the background."""
    if model_name not in AVAILABLE_MODELS:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown model: {model_name}. Available: {list(AVAILABLE_MODELS.keys())}",
        )

    status = get_fw_model_status(model_name)
    if status == "downloading":
        return FWDownloadResponse(model_name=model_name, status="downloading")
    if status == "ready":
        return FWDownloadResponse(model_name=model_name, status="ready")

    import threading

    def do_download():
        download_fw_model(model_name)

    thread = threading.Thread(target=do_download, daemon=True)
    thread.start()

    return FWDownloadResponse(model_name=model_name, status="downloading")


@app.get("/models/download_status/{model_name}", response_model=FWDownloadResponse)
async def get_fw_download_status(model_name: str):
    """Get the download status of a Faster-Whisper model."""
    status = get_fw_model_status(model_name)
    error = get_fw_download_error(model_name)
    return FWDownloadResponse(model_name=model_name, status=status, error=error)


@app.delete("/models/{model_name}", response_model=FWActionResponse)
async def delete_fw_model_endpoint(model_name: str):
    """Delete a downloaded Faster-Whisper model to free disk space."""
    if model_name not in AVAILABLE_MODELS:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown model: {model_name}",
        )

    status = get_fw_model_status(model_name)
    if status == "downloading":
        raise HTTPException(
            status_code=409,
            detail="Cannot delete model while it's downloading",
        )

    # Unload if this is the currently loaded model
    transcriber = state_manager.get_transcriber()
    current = transcriber.get_model_info()
    if current.get("model_size") == model_name and current.get("is_loaded"):
        transcriber._model_manager.unload_model()
        transcriber._model = None

    success = delete_fw_model(model_name)
    return FWActionResponse(
        success=success,
        message="Model deleted successfully" if success else "Failed to delete model",
        model_name=model_name,
    )


# ============ Settings Endpoints ============


@app.get("/settings", response_model=SettingsResponse)
async def get_settings():
    """Get current server settings."""
    return SettingsResponse(beam_size=state_manager.beam_size)


@app.post("/settings", response_model=SettingsResponse)
async def update_settings(request: SettingsUpdateRequest):
    """Update server settings."""
    if request.beam_size is not None:
        state_manager.beam_size = request.beam_size
    return SettingsResponse(beam_size=state_manager.beam_size)


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
