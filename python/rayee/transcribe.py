"""
Transcription Module

Converts audio to text using Faster-Whisper models.
"""

from typing import List, Optional, Tuple

import numpy as np

from .models import DEFAULT_MODEL, ModelManager, ModelSize


class Transcriber:
    """
    Converts audio to text using Whisper AI.

    Usage:
        transcriber = Transcriber()
        text = transcriber.transcribe(audio_data)
        print(text)
    """

    def __init__(self, model_size: ModelSize = DEFAULT_MODEL):
        """
        Initialize the transcriber.

        Args:
            model_size: Which model to use (tiny, base, small, medium, large-v3)
        """
        self._model_manager = ModelManager()
        self._model_size = model_size
        self._model = None

    def load_model(self, model_size: Optional[ModelSize] = None):
        """
        Load the transcription model.

        Args:
            model_size: Model size to load (or uses default from __init__)
        """
        if model_size:
            self._model_size = model_size
        self._model = self._model_manager.load_model(self._model_size)

    def transcribe(
        self,
        audio: np.ndarray,
        language: Optional[str] = None,
        initial_prompt: Optional[str] = None,
        beam_size: int = 5,
    ) -> str:
        """
        Convert audio to text.

        Args:
            audio: Audio data as numpy array (float32, 16kHz sample rate)
            language: Language code (e.g., "en", "es", "fr"). None = auto-detect.
            initial_prompt: Hint words/phrases to guide transcription.
                           Use this for custom vocabulary (names, jargon, etc.)

        Returns:
            Transcribed text as a string
        """
        # Load model if not already loaded
        if self._model is None:
            self.load_model()

        # Perform transcription
        segments, info = self._model.transcribe(
            audio,
            language=language,
            initial_prompt=initial_prompt,
            beam_size=beam_size,
            vad_filter=False,  # Silero VAD in vad.py already strips silence
        )

        # Combine all segments into one text string
        text_parts = []
        for segment in segments:
            text_parts.append(segment.text)

        full_text = "".join(text_parts).strip()

        return full_text

    def transcribe_with_timestamps(
        self,
        audio: np.ndarray,
        language: Optional[str] = None,
        beam_size: int = 5,
    ) -> List[Tuple[float, float, str]]:
        """
        Transcribe and return text with timing information.

        Returns:
            List of (start_time, end_time, text) tuples
        """
        if self._model is None:
            self.load_model()

        segments, info = self._model.transcribe(
            audio,
            language=language,
            beam_size=beam_size,
            vad_filter=False,
            word_timestamps=True,
        )

        results = []
        for segment in segments:
            results.append((segment.start, segment.end, segment.text.strip()))

        return results

    def get_model_info(self) -> dict:
        """Get information about the current model."""
        return {
            "model_size": self._model_size,
            "is_loaded": self._model is not None,
        }


def transcribe_audio_simple(
    audio: np.ndarray,
    model_size: ModelSize = DEFAULT_MODEL,
    language: Optional[str] = None,
) -> str:
    """
    Simple function to transcribe audio in one call.

    Args:
        audio: Audio data (numpy array, float32, 16kHz)
        model_size: Which model to use
        language: Language code or None for auto-detect

    Returns:
        Transcribed text
    """
    transcriber = Transcriber(model_size)
    return transcriber.transcribe(audio, language=language)
