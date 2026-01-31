"""
Server State Management

Tracks what the server is currently doing and manages state transitions.
"""

import threading
from enum import Enum
from typing import Optional

from .transcribe import Transcriber
from .vocabulary import VocabularyManager


# Server state - tracks what the server is currently doing
class ServerState(str, Enum):
    IDLE = "idle"  # Ready for a new command
    RECORDING = "recording"  # Microphone active, listening
    TRANSCRIBING = "transcribing"  # Processing audio to text


# Startup state - tracks model download progress
class StartupState(str, Enum):
    NOT_STARTED = "not_started"  # Haven't started yet
    DOWNLOADING_VAD = "downloading_vad"  # Downloading voice detection model
    DOWNLOADING_WHISPER = "downloading_whisper"  # Downloading transcription model
    READY = "ready"  # All models loaded, ready to transcribe
    FAILED = "failed"  # Something went wrong during startup


class ServerStateManager:
    """
    Manages server state in a thread-safe way.

    Only allows one operation at a time (recording or transcribing).
    """

    def __init__(self):
        self._state = ServerState.IDLE
        self._lock = threading.Lock()

        # Startup tracking
        self.startup_state = StartupState.NOT_STARTED
        self.startup_message = "Server starting..."
        self.startup_error: Optional[str] = None
        self.models_ready = False

        # Shared resources
        self._transcriber: Optional[Transcriber] = None
        self.vocabulary = VocabularyManager()

    @property
    def state(self) -> ServerState:
        """Current server state."""
        return self._state

    def set_state(self, new_state: ServerState) -> bool:
        """
        Try to change the server state.

        Returns True if state was changed, False if transition not allowed.
        Only allows transitioning FROM idle state (except when going back to idle).
        """
        with self._lock:
            # Always allow transitioning back to idle
            if new_state == ServerState.IDLE:
                self._state = new_state
                return True

            # Only allow starting new operations from idle
            if self._state != ServerState.IDLE:
                return False

            self._state = new_state
            return True

    def get_transcriber(self) -> Transcriber:
        """Get or create the transcriber instance."""
        if self._transcriber is None:
            self._transcriber = Transcriber()
        return self._transcriber

    def set_transcriber(self, transcriber: Transcriber):
        """Replace the transcriber instance (used when switching models)."""
        self._transcriber = transcriber

    def set_startup_state(
        self, state: StartupState, message: str, error: Optional[str] = None
    ):
        """Update startup state with message."""
        self.startup_state = state
        self.startup_message = message
        self.startup_error = error
        if state == StartupState.READY:
            self.models_ready = True


# Global instance
state_manager = ServerStateManager()
