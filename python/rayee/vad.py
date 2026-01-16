"""
Voice Activity Detection (VAD) Module

Detects when someone is speaking vs. silence.
Used to automatically stop recording when the user stops talking.
"""

import numpy as np
import torch
import sounddevice as sd
from typing import Optional, Callable
import threading
import time

from .audio import SAMPLE_RATE, CHANNELS

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

    def load_model(self):
        """Load the Silero VAD model (downloads on first use)."""
        if self._model is not None:
            return

        print("Loading voice activity detection model...")
        # Load Silero VAD from torch hub
        self._model, self._utils = torch.hub.load(
            repo_or_dir='snakers4/silero-vad',
            model='silero_vad',
            force_reload=False,
            onnx=False,
            trust_repo=True
        )
        print("VAD model loaded.")

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

        # Convert to torch tensor
        audio_tensor = torch.from_numpy(audio_chunk).float()

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
            chunk = audio_buffer[i:i + VAD_CHUNK_SAMPLES]
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
        silence_threshold: float = 0.5,      # How confident we need to be it's speech
        silence_duration: float = 1.5,        # Seconds of silence before stopping
        max_duration: float = 60.0,           # Maximum recording length
        min_speech_duration: float = 0.3,     # Minimum speech before we start "listening"
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

        print("Listening... (speak now)")

        # Open audio stream
        with sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype='float32',
            blocksize=chunk_size
        ) as stream:
            while self._is_recording and not self._stop_requested:
                # Check max duration
                elapsed = time.time() - recording_start_time
                if elapsed >= self.max_duration:
                    print(f"\nMax duration ({self.max_duration}s) reached.")
                    break

                # Read audio chunk (exactly 512 samples for VAD)
                audio_chunk, overflowed = stream.read(chunk_size)
                audio_chunk = audio_chunk.flatten()

                # Check for speech using 512-sample chunk
                is_speech = self._vad.is_speech(audio_chunk, self.silence_threshold)

                if is_speech:
                    if not speech_started:
                        # First speech detected!
                        speech_started = True
                        speech_start_time = time.time()
                        if on_speech_start:
                            on_speech_start()
                        print("Speech detected, recording...")

                    last_speech_time = time.time()
                    audio_chunks.append(audio_chunk)

                elif speech_started:
                    # Silence after speech
                    audio_chunks.append(audio_chunk)

                    # Check if silence has lasted long enough
                    silence_elapsed = time.time() - last_speech_time
                    if silence_elapsed >= self.silence_duration:
                        print(f"\nSilence detected for {self.silence_duration}s, stopping.")
                        break

        self._is_recording = False

        if on_speech_end:
            on_speech_end()

        # Combine all chunks
        if audio_chunks:
            audio_data = np.concatenate(audio_chunks)
            duration = len(audio_data) / SAMPLE_RATE
            print(f"Recorded {duration:.2f} seconds of audio")
            return audio_data
        else:
            print("No speech detected.")
            return np.array([], dtype='float32')

    def stop(self):
        """Manually stop the recording."""
        self._stop_requested = True

    def is_recording(self) -> bool:
        """Check if currently recording."""
        return self._is_recording
