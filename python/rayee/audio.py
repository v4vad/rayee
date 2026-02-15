"""
Audio Recording Module

Handles recording audio from the microphone using sounddevice.
"""

import queue
import threading
from typing import Optional

import numpy as np
import sounddevice as sd

# Audio settings - these values work well for speech recognition
SAMPLE_RATE = 16000  # 16kHz is what Whisper expects
CHANNELS = 1  # Mono audio (one channel)


class AudioRecorder:
    """
    Records audio from the microphone.

    Usage:
        recorder = AudioRecorder()
        recorder.start()
        # ... speak into microphone ...
        audio_data = recorder.stop()
    """

    def __init__(self, sample_rate: int = SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.is_recording = False
        self._audio_queue = queue.Queue()
        self._recorded_chunks = []
        self._stream: Optional[sd.InputStream] = None

    def _audio_callback(self, indata, frames, time, status):
        """Called by sounddevice for each audio chunk while recording."""
        if status:
            print(f"Audio status: {status}")
        # Put a copy of the audio data in our queue
        self._audio_queue.put(indata.copy())

    def start(self):
        """Start recording from the microphone."""
        if self.is_recording:
            print("Already recording!")
            return

        self._recorded_chunks = []
        self.is_recording = True

        # Open audio stream from microphone
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=CHANNELS,
            dtype="float32",
            callback=self._audio_callback,
        )
        self._stream.start()
        print("Recording started...")

    def stop(self) -> np.ndarray:
        """
        Stop recording and return the audio data.

        Returns:
            numpy array of audio samples (float32, mono, 16kHz)
        """
        if not self.is_recording:
            print("Not currently recording!")
            return np.array([], dtype="float32")

        self.is_recording = False

        # Stop and close the stream
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

        # Collect all audio chunks from the queue
        while not self._audio_queue.empty():
            self._recorded_chunks.append(self._audio_queue.get())

        print("Recording stopped.")

        if not self._recorded_chunks:
            return np.array([], dtype="float32")

        # Combine all chunks into one array
        audio_data = np.concatenate(self._recorded_chunks, axis=0)

        # Flatten to 1D array (remove channel dimension)
        audio_data = audio_data.flatten()

        duration = len(audio_data) / self.sample_rate
        print(f"Recorded {duration:.2f} seconds of audio")

        return audio_data

    def get_current_duration(self) -> float:
        """Get how long we've been recording (in seconds)."""
        if not self._recorded_chunks:
            return 0.0
        total_samples = sum(chunk.shape[0] for chunk in self._recorded_chunks)
        return total_samples / self.sample_rate


def record_for_duration(duration: float, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """
    Simple function to record for a fixed duration.

    Args:
        duration: How long to record in seconds
        sample_rate: Audio sample rate (default 16000 Hz)

    Returns:
        numpy array of audio samples
    """
    print(f"Recording for {duration} seconds...")
    audio_data = sd.rec(
        int(duration * sample_rate),
        samplerate=sample_rate,
        channels=CHANNELS,
        dtype="float32",
    )
    sd.wait()  # Wait until recording is finished
    print("Recording complete.")
    return audio_data.flatten()


def list_audio_devices():
    """Print a list of available audio input devices."""
    print("Available audio devices:")
    print(sd.query_devices())
    print(f"\nDefault input device: {sd.query_devices(kind='input')['name']}")
