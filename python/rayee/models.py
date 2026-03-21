"""
Model Management Module

Handles loading and switching between different Whisper models.
Models are downloaded automatically on first use from Hugging Face.
"""

import gc
import shutil
import threading
from pathlib import Path
from typing import Literal, Optional

from faster_whisper import WhisperModel

# Timeout for downloading the Whisper model (10 minutes)
# Larger models can take a while to download
WHISPER_DOWNLOAD_TIMEOUT = 600


# Available model sizes - larger = more accurate but slower
# tiny:   ~75MB, fastest, good for testing
# base:   ~145MB, fast
# small:  ~488MB, good balance (recommended for most users)
# medium: ~1.5GB, better accuracy
# large:  ~3GB, best accuracy, needs more RAM

ModelSize = Literal[
    "tiny",
    "base",
    "small",
    "medium",
    "large-v3",
    "large-v3-turbo",
    "distil-small.en",
    "distil-medium.en",
    "distil-large-v3",
]

AVAILABLE_MODELS = {
    "tiny": {
        "name": "tiny",
        "description": "Fastest, lowest accuracy (good for testing)",
        "size_mb": 75,
        "category": "standard",
    },
    "base": {
        "name": "base",
        "description": "Fast with reasonable accuracy",
        "size_mb": 145,
        "category": "standard",
    },
    "small": {
        "name": "small",
        "description": "Good balance of speed and accuracy (recommended)",
        "size_mb": 488,
        "category": "standard",
    },
    "medium": {
        "name": "medium",
        "description": "Better accuracy, slower",
        "size_mb": 1500,
        "category": "standard",
    },
    "large-v3": {
        "name": "large-v3",
        "description": "Best accuracy, slowest, needs more memory",
        "size_mb": 3000,
        "category": "standard",
    },
    "large-v3-turbo": {
        "name": "large-v3-turbo",
        "description": "Near-best accuracy, much faster than large-v3",
        "size_mb": 1600,
        "category": "standard",
    },
    "distil-small.en": {
        "name": "distil-small.en",
        "description": "Fast English-only, distilled from small",
        "size_mb": 330,
        "category": "distil",
    },
    "distil-medium.en": {
        "name": "distil-medium.en",
        "description": "Balanced English-only, distilled from medium",
        "size_mb": 750,
        "category": "distil",
    },
    "distil-large-v3": {
        "name": "distil-large-v3",
        "description": "Best English-only, distilled from large-v3",
        "size_mb": 1400,
        "category": "distil",
    },
}

DEFAULT_MODEL = "small"

# Faster-Whisper models are hosted on HuggingFace under this org
FW_REPO_PREFIX = "Systran/faster-whisper-"
DISTIL_REPO_PREFIX = "Systran/faster-distil-whisper-"

# Track download state for Faster-Whisper models
_fw_download_progress: dict[str, str] = (
    {}
)  # model_name -> "downloading"/"ready"/"error"
_fw_download_errors: dict[str, str] = {}  # model_name -> error message
_fw_download_lock = threading.Lock()


def get_fw_repo_id(model_name: str) -> str:
    """Get the HuggingFace repo ID for a Faster-Whisper model."""
    model_info = AVAILABLE_MODELS.get(model_name, {})
    if model_info.get("category") == "distil":
        # distil-small.en -> small.en (strip "distil-" prefix)
        short_name = model_name.removeprefix("distil-")
        return f"{DISTIL_REPO_PREFIX}{short_name}"
    return f"{FW_REPO_PREFIX}{model_name}"


def is_fw_model_downloaded(model_name: str) -> bool:
    """Check if a Faster-Whisper model exists in the HuggingFace cache."""
    repo_id = get_fw_repo_id(model_name)
    cache_dir = Path.home() / ".cache" / "huggingface" / "hub"
    model_dir = cache_dir / f"models--{repo_id.replace('/', '--')}"
    snapshots_dir = model_dir / "snapshots"
    return snapshots_dir.is_dir() and any(snapshots_dir.iterdir())


def get_fw_model_status(model_name: str) -> str:
    """Get the current download status of a Faster-Whisper model."""
    with _fw_download_lock:
        if model_name in _fw_download_progress:
            return _fw_download_progress[model_name]
    if is_fw_model_downloaded(model_name):
        return "ready"
    if model_name in _fw_download_errors:
        return "error"
    return "not_downloaded"


def get_fw_download_error(model_name: str) -> Optional[str]:
    """Get the download error for a Faster-Whisper model, if any."""
    return _fw_download_errors.get(model_name)


def download_fw_model(model_name: str) -> bool:
    """Download a Faster-Whisper model to the HuggingFace cache."""
    if model_name not in AVAILABLE_MODELS:
        _fw_download_errors[model_name] = f"Unknown model: {model_name}"
        return False

    with _fw_download_lock:
        _fw_download_progress[model_name] = "downloading"
        _fw_download_errors.pop(model_name, None)

    try:
        from huggingface_hub import snapshot_download

        repo_id = get_fw_repo_id(model_name)
        print(f"Downloading Faster-Whisper model: {model_name} from {repo_id}")
        snapshot_download(repo_id=repo_id)

        with _fw_download_lock:
            _fw_download_progress[model_name] = "ready"

        print(f"Model {model_name} downloaded successfully")
        return True

    except Exception as e:
        error_msg = str(e)
        _fw_download_errors[model_name] = error_msg
        with _fw_download_lock:
            _fw_download_progress.pop(model_name, None)
        print(f"Error downloading model {model_name}: {error_msg}")
        return False


def delete_fw_model(model_name: str) -> bool:
    """Delete a Faster-Whisper model from the HuggingFace cache."""
    repo_id = get_fw_repo_id(model_name)
    cache_dir = Path.home() / ".cache" / "huggingface" / "hub"
    model_dir = cache_dir / f"models--{repo_id.replace('/', '--')}"
    if model_dir.is_dir():
        try:
            shutil.rmtree(model_dir)
            print(f"Deleted Faster-Whisper model: {model_name}")
            with _fw_download_lock:
                _fw_download_progress.pop(model_name, None)
                _fw_download_errors.pop(model_name, None)
            return True
        except Exception as e:
            print(f"Error deleting model {model_name}: {e}")
            return False
    return True  # Already gone


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
        timeout: int = WHISPER_DOWNLOAD_TIMEOUT,
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

        # Unload previous model to free memory before loading new one
        if self._current_model is not None:
            print(
                f"Unloading model '{self._current_model_name}' before loading '{model_size}'..."
            )
            del self._current_model
            self._current_model = None
            self._current_model_name = None
            gc.collect()

        if model_size not in AVAILABLE_MODELS:
            raise ValueError(
                f"Unknown model: {model_size}. "
                f"Available: {list(AVAILABLE_MODELS.keys())}"
            )

        model_info = AVAILABLE_MODELS[model_size]
        print(f"Loading model: {model_size} ({model_info['description']})")
        print(
            f"This may take a few minutes on first run (downloading ~{model_info['size_mb']}MB)..."
        )

        # Use a thread with timeout to prevent hanging forever during download
        result = {"model": None, "error": None}

        def download_model():
            try:
                # Load the model
                # - device="auto" uses GPU if available, else CPU
                # - compute_type="auto" picks optimal precision for the hardware
                result["model"] = WhisperModel(
                    model_size, device=device, compute_type=compute_type
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
