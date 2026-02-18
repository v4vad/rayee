"""
MLX Model Manager

Manages loading, caching, and unloading the local LLM used for
text transformations. Uses MLX for fast Apple Silicon inference.

The model is lazy-loaded on first use and unloaded after 30 seconds
of inactivity to free ~800MB of RAM.
"""

import os
import threading
import time

# Model configuration
MODEL_ID = "mlx-community/Llama-3.2-1B-Instruct-4bit"
MODEL_CACHE_DIR = os.path.expanduser("~/.rayee/llm_models")
DEFAULT_MAX_TOKENS = 512
UNLOAD_DELAY_SECONDS = 30


class MLXModelManager:
    """Singleton that manages the MLX LLM lifecycle."""

    _instance = None
    _lock = threading.Lock()

    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self._initialized = True

        self._model = None
        self._tokenizer = None
        self._model_lock = threading.Lock()
        self._unload_timer = None
        self._last_used = 0.0
        self._downloading = False
        self._download_error = None

    @property
    def is_model_loaded(self) -> bool:
        return self._model is not None

    @property
    def is_model_downloaded(self) -> bool:
        """Check if the model files exist on disk."""
        if not os.path.exists(MODEL_CACHE_DIR):
            return False
        # Check for the model's subdirectory
        model_dir = os.path.join(MODEL_CACHE_DIR, MODEL_ID.replace("/", "--"))
        if os.path.isdir(model_dir):
            # Check for key model files
            return any(
                f.endswith((".safetensors", ".gguf")) for f in os.listdir(model_dir)
            )
        # Also check huggingface cache structure
        return self._check_hf_cache()

    @property
    def is_downloading(self) -> bool:
        return self._downloading

    @property
    def download_error(self) -> str | None:
        return self._download_error

    def load_model(self):
        """Load the model into memory. Thread-safe."""
        with self._model_lock:
            if self._model is not None:
                return

            from mlx_lm import load

            print(f"[MLX] Loading model: {MODEL_ID}")
            os.makedirs(MODEL_CACHE_DIR, exist_ok=True)

            self._model, self._tokenizer = load(
                MODEL_ID,
                tokenizer_config={"trust_remote_code": False},
            )
            self._last_used = time.time()
            print("[MLX] Model loaded successfully")

    def unload_model(self):
        """Unload the model from memory to free RAM."""
        with self._model_lock:
            if self._model is None:
                return
            self._model = None
            self._tokenizer = None
            self._cancel_unload_timer()
            print("[MLX] Model unloaded to free memory")

    def generate(
        self, system_prompt: str, user_prompt: str, max_tokens: int = DEFAULT_MAX_TOKENS
    ) -> str:
        """Generate text using the loaded model.

        Args:
            system_prompt: System instruction for the LLM.
            user_prompt: User message with the text to transform.
            max_tokens: Maximum tokens to generate.

        Returns:
            Generated text string.
        """
        if self._model is None:
            self.load_model()

        from mlx_lm import generate as mlx_generate

        # Build chat messages in Llama instruct format
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        prompt = self._tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )

        with self._model_lock:
            self._last_used = time.time()
            result = mlx_generate(
                self._model,
                self._tokenizer,
                prompt=prompt,
                max_tokens=max_tokens,
                verbose=False,
            )

        self._schedule_unload()
        return result

    def download_model(self):
        """Download the model files to disk (blocking)."""
        self._downloading = True
        self._download_error = None
        try:
            from huggingface_hub import snapshot_download

            print(f"[MLX] Downloading model: {MODEL_ID}")
            os.makedirs(MODEL_CACHE_DIR, exist_ok=True)
            snapshot_download(
                MODEL_ID,
                local_dir=os.path.join(MODEL_CACHE_DIR, MODEL_ID.replace("/", "--")),
            )
            print("[MLX] Model download complete")
        except Exception as e:
            self._download_error = str(e)
            print(f"[MLX] Download failed: {e}")
            raise
        finally:
            self._downloading = False

    def _schedule_unload(self):
        """Schedule model unload after inactivity timeout."""
        self._cancel_unload_timer()
        self._unload_timer = threading.Timer(
            UNLOAD_DELAY_SECONDS, self._check_and_unload
        )
        self._unload_timer.daemon = True
        self._unload_timer.start()

    def _cancel_unload_timer(self):
        if self._unload_timer is not None:
            self._unload_timer.cancel()
            self._unload_timer = None

    def _check_and_unload(self):
        """Unload model if it hasn't been used recently."""
        elapsed = time.time() - self._last_used
        if elapsed >= UNLOAD_DELAY_SECONDS:
            self.unload_model()

    def _check_hf_cache(self) -> bool:
        """Check if model exists in HuggingFace cache."""
        hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
        if not os.path.exists(hf_cache):
            return False
        model_slug = "models--" + MODEL_ID.replace("/", "--")
        model_path = os.path.join(hf_cache, model_slug)
        return os.path.isdir(model_path)
