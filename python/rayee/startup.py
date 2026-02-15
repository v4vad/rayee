"""
Server Startup and Shutdown

Handles model preloading and cleanup when server starts/stops.
"""

import asyncio
from concurrent.futures import ThreadPoolExecutor

from .state import StartupState, state_manager
from .vad import VoiceActivityDetector

# Server configuration
HOST = "127.0.0.1"  # localhost only - secure
PORT = 8765

# Dedicated executor for audio/transcription work
# Using a single worker ensures audio operations don't compete for resources
# and helps with macOS audio thread requirements
audio_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="rayee_audio")

# Separate executor for upload transcription work
# This lets uploads run in their own thread without competing with recording
upload_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="rayee_upload")


def print_startup_banner():
    """Print the startup message with available endpoints."""
    print(f"\n{'='*50}")
    print("  Rayee Transcription Server Started")
    print(f"  Running on http://{HOST}:{PORT}")
    print(f"{'='*50}")
    print("\nEndpoints:")
    print("  GET  /status         - Server status")
    print("  GET  /startup_status - Model loading status")
    print("  POST /transcribe     - Record and transcribe")
    print("  POST /transcribe_file - Transcribe WAV file")
    print("  POST /transcribe_upload - Transcribe uploaded file (background)")
    print("  GET  /models         - List available models")
    print("  POST /model          - Switch model")
    print("  GET  /vocabulary     - List custom words")
    print("  POST /vocabulary     - Add custom word")
    print("  DELETE /vocabulary/{word} - Remove word")


def preload_models():
    """
    Load AI models in background.

    This runs in a separate thread so the server stays responsive
    while models download (which can take minutes on first run).
    """
    try:
        # Step 1: Load VAD model
        state_manager.set_startup_state(
            StartupState.DOWNLOADING_VAD, "Downloading voice detection model..."
        )
        print(f"[Startup] {state_manager.startup_message}")

        vad = VoiceActivityDetector()
        vad.load_model()

        # Step 2: Load Whisper model
        state_manager.set_startup_state(
            StartupState.DOWNLOADING_WHISPER, "Downloading transcription model..."
        )
        print(f"[Startup] {state_manager.startup_message}")

        transcriber = state_manager.get_transcriber()
        transcriber.load_model()

        # All done!
        state_manager.set_startup_state(
            StartupState.READY, "All models loaded. Ready to transcribe!"
        )
        print(f"[Startup] {state_manager.startup_message}")
        print("\nReady for requests!\n")

    except TimeoutError as e:
        state_manager.set_startup_state(
            StartupState.FAILED, "Model download timed out", str(e)
        )
        print(f"[Startup] ERROR: {e}")

    except Exception as e:
        state_manager.set_startup_state(
            StartupState.FAILED, "Failed to load models", str(e)
        )
        print(f"[Startup] ERROR: {e}")


async def on_startup():
    """Called when the FastAPI server starts."""
    print_startup_banner()
    print("\nPreloading AI models (this may take a few minutes on first run)...")

    # Run model loading in the audio executor thread
    # This keeps the server responsive while models download
    loop = asyncio.get_running_loop()
    loop.run_in_executor(audio_executor, preload_models)


async def on_shutdown():
    """Called when the FastAPI server shuts down."""
    print("Server shutting down...")
    # Wait for executors to finish their current tasks before shutting down
    # This prevents "cannot schedule new futures" errors during model loading
    audio_executor.shutdown(wait=True, cancel_futures=False)
    upload_executor.shutdown(wait=True, cancel_futures=False)
    print("All background tasks completed.")


def run_server(host: str = HOST, port: int = PORT):
    """
    Start the server.

    Args:
        host: Host to bind to (default: 127.0.0.1)
        port: Port to listen on (default: 8765)
    """
    import uvicorn

    from .server import app

    uvicorn.run(app, host=host, port=port)
