"""
Model Management Module

Handles loading and switching between different Whisper models.
Models are downloaded automatically on first use from Hugging Face.
"""

from faster_whisper import WhisperModel
from typing import Optional, Literal
import os
import threading

# Timeout for downloading the Whisper model (10 minutes)
# Larger models can take a while to download
WHISPER_DOWNLOAD_TIMEOUT = 600


# Available model sizes - larger = more accurate but slower
# tiny:   ~75MB, fastest, good for testing
# base:   ~145MB, fast
# small:  ~488MB, good balance (recommended for most users)
# medium: ~1.5GB, better accuracy
# large:  ~3GB, best accuracy, needs more RAM

ModelSize = Literal["tiny", "base", "small", "medium", "large-v3"]

AVAILABLE_MODELS = {
    "tiny": {
        "name": "tiny",
        "description": "Fastest, lowest accuracy (good for testing)",
        "size_mb": 75,
    },
    "base": {
        "name": "base",
        "description": "Fast with reasonable accuracy",
        "size_mb": 145,
    },
    "small": {
        "name": "small",
        "description": "Good balance of speed and accuracy (recommended)",
        "size_mb": 488,
    },
    "medium": {
        "name": "medium",
        "description": "Better accuracy, slower",
        "size_mb": 1500,
    },
    "large-v3": {
        "name": "large-v3",
        "description": "Best accuracy, slowest, needs more memory",
        "size_mb": 3000,
    },
}

DEFAULT_MODEL = "small"


class ModelManager:
    """
    Manages Whisper models for transcription.

    The model is downloaded automatically on first use.
    Models are cached locally so subsequent loads are fast.

    Usage:
        manager = ModelManager()
        model = manager.load_model("small")
        # Use model for transcription...
    """

    def __init__(self):
        self._current_model: Optional[WhisperModel] = None
        self._current_model_name: Optional[str] = None

    def load_model(
        self,
        model_size: ModelSize = DEFAULT_MODEL,
        device: str = "auto",
        compute_type: str = "auto",
        timeout: int = WHISPER_DOWNLOAD_TIMEOUT
    ) -> WhisperModel:
        """
        Load a Whisper model.

        Args:
            model_size: Size of model to load (tiny, base, small, medium, large-v3)
            device: "cpu", "cuda", or "auto" (auto detects best option)
            compute_type: Precision for computation ("auto" picks optimal)
            timeout: Maximum seconds to wait for download (default: 10 minutes)

        Returns:
            Loaded WhisperModel ready for transcription

        Raises:
            TimeoutError: If download takes longer than timeout
            ValueError: If model_size is not valid
        """
        # If we already have this model loaded, return it
        if self._current_model and self._current_model_name == model_size:
            print(f"Model '{model_size}' already loaded.")
            return self._current_model

        if model_size not in AVAILABLE_MODELS:
            raise ValueError(
                f"Unknown model: {model_size}. "
                f"Available: {list(AVAILABLE_MODELS.keys())}"
            )

        model_info = AVAILABLE_MODELS[model_size]
        print(f"Loading model: {model_size} ({model_info['description']})")
        print(f"This may take a few minutes on first run (downloading ~{model_info['size_mb']}MB)...")

        # Use a thread with timeout to prevent hanging forever during download
        result = {"model": None, "error": None}

        def download_model():
            try:
                # Load the model
                # - device="auto" uses GPU if available, else CPU
                # - compute_type="auto" picks optimal precision for the hardware
                result["model"] = WhisperModel(
                    model_size,
                    device=device,
                    compute_type=compute_type
                )
            except Exception as e:
                result["error"] = e

        download_thread = threading.Thread(target=download_model)
        download_thread.start()
        download_thread.join(timeout=timeout)

        if download_thread.is_alive():
            # Download timed out
            raise TimeoutError(
                f"Whisper model download timed out after {timeout} seconds. "
                "Check your internet connection and try again."
            )

        if result["error"]:
            raise result["error"]

        self._current_model = result["model"]
        self._current_model_name = model_size

        print(f"Model '{model_size}' loaded successfully!")
        return self._current_model

    def get_current_model(self) -> Optional[WhisperModel]:
        """Get the currently loaded model, or None if no model is loaded."""
        return self._current_model

    def get_current_model_name(self) -> Optional[str]:
        """Get the name of the currently loaded model."""
        return self._current_model_name

    def unload_model(self):
        """Unload the current model to free memory."""
        if self._current_model:
            del self._current_model
            self._current_model = None
            self._current_model_name = None
            print("Model unloaded.")
        else:
            print("No model currently loaded.")


def list_available_models():
    """Print information about available models."""
    print("\nAvailable Whisper Models:")
    print("-" * 60)
    for name, info in AVAILABLE_MODELS.items():
        rec = " (RECOMMENDED)" if name == DEFAULT_MODEL else ""
        print(f"  {name:12} - {info['description']}{rec}")
        print(f"              Size: ~{info['size_mb']}MB")
    print("-" * 60)
