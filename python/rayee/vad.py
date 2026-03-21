"""
Voice Activity Detection (VAD) Module

Detects when someone is speaking vs. silence.
Used to automatically stop recording when the user stops talking.
"""

import logging
import signal
import threading
import time
from typing import Callable, Optional

import numpy as np
import sounddevice as sd
import torch

from .audio import CHANNELS, SAMPLE_RATE

logger = logging.getLogger(__name__)


def trim_trailing_silence(
    audio: np.ndarray,
    sample_rate: int,
    threshold: float = 0.01,
    pad_seconds: float = 0.05,
) -> np.ndarray:
    """Remove trailing silence from audio, keeping a small pad."""
    above = np.where(np.abs(audio) > threshold)[0]
    if len(above) == 0:
        return audio
    last_speech = above[-1]
    pad_samples = int(pad_seconds * sample_rate)
    return audio[: last_speech + pad_samples]


# Timeout for downloading the VAD model (5 minutes)
VAD_DOWNLOAD_TIMEOUT = 300

# Silero VAD requires exactly this many samples per call
# 512 samples at 16kHz = 32 milliseconds
VAD_CHUNK_SAMPLES = 512


class VoiceActivityDetector:
    """
    Detects voice activity using Silero VAD model.

    The Silero VAD model is lightweight and fast, perfect for
    real-time voice detection on CPU.
    """

    def __init__(self):
        self._model = None
        self._utils = None

    def load_model(self, timeout: int = VAD_DOWNLOAD_TIMEOUT):
        """
        Load the Silero VAD model (downloads on first use).

        Args:
            timeout: Maximum seconds to wait for download (default: 5 minutes)

        Raises:
            TimeoutError: If download takes longer than timeout
            Exception: If download fails for other reasons
        """
        if self._model is not None:
            return

        logger.info("Loading voice activity detection model...")
        logger.info(
            "(This may take a few minutes on first run while the model downloads)"
        )

        # Use a thread with timeout to prevent hanging forever
        result = {"model": None, "utils": None, "error": None}

        def download_model():
            try:
                model, utils = torch.hub.load(
                    repo_or_dir="snakers4/silero-vad",
                    model="silero_vad",
                    force_reload=False,
                    onnx=False,
                    trust_repo=True,
                )
                result["model"] = model
                result["utils"] = utils
            except Exception as e:
                result["error"] = e

        download_thread = threading.Thread(target=download_model)
        download_thread.start()
        download_thread.join(timeout=timeout)

        if download_thread.is_alive():
            # Download timed out
            raise TimeoutError(
                f"VAD model download timed out after {timeout} seconds. "
                "Check your internet connection and try again."
            )

        if result["error"]:
            raise result["error"]

        self._model = result["model"]
        self._utils = result["utils"]
        logger.info("VAD model loaded.")

    def is_speech(self, audio_chunk: np.ndarray, threshold: float = 0.5) -> bool:
        """
        Check if an audio chunk contains speech.

        Args:
            audio_chunk: Audio segment of exactly VAD_CHUNK_SAMPLES (512 samples)
            threshold: Confidence threshold (0-1). Higher = stricter.

        Returns:
            True if speech detected, False otherwise
        """
        if self._model is None:
            self.load_model()

        # Silero VAD requires exactly 512 samples at 16kHz
        if len(audio_chunk) != VAD_CHUNK_SAMPLES:
            raise ValueError(
                f"VAD requires exactly {VAD_CHUNK_SAMPLES} samples, got {len(audio_chunk)}"
            )

        # Convert to torch tensor (audio_chunk is already float32)
        audio_tensor = torch.from_numpy(audio_chunk)

        # Get speech probability
        speech_prob = self._model(audio_tensor, SAMPLE_RATE).item()

        return speech_prob >= threshold

    def check_speech_in_buffer(
        self, audio_buffer: np.ndarray, threshold: float = 0.5
    ) -> bool:
        """
        Check if any part of an audio buffer contains speech.

        Processes the buffer in VAD_CHUNK_SAMPLES windows.

        Args:
            audio_buffer: Audio data (can be any length)
            threshold: Confidence threshold (0-1)

        Returns:
            True if speech detected in any window
        """
        if self._model is None:
            self.load_model()

        # Process in 512-sample windows
        for i in range(0, len(audio_buffer) - VAD_CHUNK_SAMPLES + 1, VAD_CHUNK_SAMPLES):
            chunk = audio_buffer[i : i + VAD_CHUNK_SAMPLES]
            if self.is_speech(chunk, threshold):
                return True

        return False


class SmartRecorder:
    """
    Records audio with automatic stop when you finish speaking.

    This recorder:
    1. Waits for you to start speaking
    2. Records while you're talking
    3. Automatically stops after you've been silent for a while

    Usage:
        recorder = SmartRecorder()
        audio = recorder.record()  # Blocks until recording complete
        # Now audio contains what you said
    """

    def __init__(
        self,
        silence_threshold: float = 0.5,  # How confident we need to be it's speech
        silence_duration: float = 1.5,  # Seconds of silence before stopping
        max_duration: float = 60.0,  # Maximum recording length
        min_speech_duration: float = 0.3,  # Minimum speech before we start "listening"
    ):
        """
        Initialize the smart recorder.

        Args:
            silence_threshold: VAD confidence threshold (0-1)
            silence_duration: How long to wait after speech stops (seconds)
            max_duration: Maximum recording time (seconds)
            min_speech_duration: Minimum speech needed before recording starts
        """
        self.silence_threshold = silence_threshold
        self.silence_duration = silence_duration
        self.max_duration = max_duration
        self.min_speech_duration = min_speech_duration

        self._vad = VoiceActivityDetector()
        self._is_recording = False
        self._stop_requested = False

    def record(
        self,
        on_speech_start: Optional[Callable] = None,
        on_speech_end: Optional[Callable] = None,
    ) -> np.ndarray:
        """
        Record audio with automatic stop.

        Args:
            on_speech_start: Callback when speech is first detected
            on_speech_end: Callback when recording stops

        Returns:
            Recorded audio as numpy array
        """
        self._vad.load_model()

        # Audio collection
        audio_chunks = []
        # Use exactly 512 samples as required by Silero VAD
        chunk_size = VAD_CHUNK_SAMPLES

        # State tracking
        speech_started = False
        speech_start_time = None
        last_speech_time = None
        recording_start_time = time.time()

        self._is_recording = True
        self._stop_requested = False

        logger.info("Listening... (speak now)")

        try:
            default_device = sd.query_devices(kind="input")
            logger.debug("Using input device: %s", default_device["name"])
        except Exception as e:
            logger.debug("Could not query input device: %s", e)

        # Open audio stream
        with sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="float32",
            blocksize=chunk_size,
        ) as stream:
            while self._is_recording and not self._stop_requested:
                # Check max duration
                elapsed = time.time() - recording_start_time
                if elapsed >= self.max_duration:
                    logger.info("Max duration (%.0fs) reached.", self.max_duration)
                    break

                # Read audio chunk (exactly 512 samples for VAD)
                audio_chunk, overflowed = stream.read(chunk_size)
                audio_chunk = audio_chunk[:, 0] if audio_chunk.ndim > 1 else audio_chunk

                # Check for speech using 512-sample chunk
                is_speech = self._vad.is_speech(audio_chunk, self.silence_threshold)

                if is_speech:
                    if not speech_started:
                        if speech_start_time is None:
                            # First speech chunk — start probation
                            speech_start_time = time.time()
                        audio_chunks.append(audio_chunk)
                        # Only confirm speech after min_speech_duration
                        if time.time() - speech_start_time >= self.min_speech_duration:
                            speech_started = True
                            if on_speech_start:
                                on_speech_start()
                            logger.info("Speech detected, recording...")
                    else:
                        audio_chunks.append(audio_chunk)

                    last_speech_time = time.time()

                elif speech_started:
                    # Silence after confirmed speech
                    audio_chunks.append(audio_chunk)

                    # Check if silence has lasted long enough
                    silence_elapsed = time.time() - last_speech_time
                    if silence_elapsed >= self.silence_duration:
                        logger.info(
                            "Silence detected for %.1fs, stopping.",
                            self.silence_duration,
                        )
                        break

                else:
                    # Silence during probation — reset
                    if speech_start_time is not None:
                        speech_start_time = None
                        audio_chunks.clear()

        self._is_recording = False

        if on_speech_end:
            on_speech_end()

        # Combine all chunks
        if audio_chunks:
            audio_data = np.concatenate(audio_chunks)
            audio_data = trim_trailing_silence(audio_data, SAMPLE_RATE)
            duration = len(audio_data) / SAMPLE_RATE
            logger.info("Recorded %.2f seconds of audio", duration)
            return audio_data
        else:
            logger.info("No speech detected.")
            return np.array([], dtype="float32")

    def stop(self):
        """Manually stop the recording."""
        self._stop_requested = True

    def is_recording(self) -> bool:
        """Check if currently recording."""
        return self._is_recording
