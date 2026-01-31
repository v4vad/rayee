"""
Tests for server state management.

Run with: cd python && pytest tests/ -v
"""

import pytest
from rayee.state import ServerState, ServerStateManager, StartupState


class TestServerStateManager:
    """Test the ServerStateManager class."""

    def test_initial_state_is_idle(self):
        """Server should start in IDLE state."""
        manager = ServerStateManager()
        assert manager.state == ServerState.IDLE

    def test_can_transition_from_idle_to_recording(self):
        """Should allow transitioning from IDLE to RECORDING."""
        manager = ServerStateManager()
        result = manager.set_state(ServerState.RECORDING)
        assert result is True
        assert manager.state == ServerState.RECORDING

    def test_cannot_start_recording_while_recording(self):
        """Should not allow starting recording while already recording."""
        manager = ServerStateManager()
        manager.set_state(ServerState.RECORDING)

        # Try to start recording again
        result = manager.set_state(ServerState.RECORDING)
        assert result is False
        assert manager.state == ServerState.RECORDING

    def test_cannot_start_transcribing_while_recording(self):
        """Should not allow starting transcription while recording."""
        manager = ServerStateManager()
        manager.set_state(ServerState.RECORDING)

        # Try to start transcribing
        result = manager.set_state(ServerState.TRANSCRIBING)
        assert result is False
        assert manager.state == ServerState.RECORDING

    def test_can_always_transition_to_idle(self):
        """Should always allow transitioning back to IDLE."""
        manager = ServerStateManager()
        manager.set_state(ServerState.RECORDING)

        result = manager.set_state(ServerState.IDLE)
        assert result is True
        assert manager.state == ServerState.IDLE

    def test_startup_state_initially_not_started(self):
        """Startup state should be NOT_STARTED initially."""
        manager = ServerStateManager()
        assert manager.startup_state == StartupState.NOT_STARTED
        assert manager.models_ready is False

    def test_set_startup_state_updates_message(self):
        """Setting startup state should update the message."""
        manager = ServerStateManager()
        manager.set_startup_state(
            StartupState.DOWNLOADING_VAD, "Downloading VAD model..."
        )

        assert manager.startup_state == StartupState.DOWNLOADING_VAD
        assert manager.startup_message == "Downloading VAD model..."

    def test_ready_state_sets_models_ready(self):
        """Setting READY state should set models_ready to True."""
        manager = ServerStateManager()
        manager.set_startup_state(StartupState.READY, "Ready!")

        assert manager.startup_state == StartupState.READY
        assert manager.models_ready is True

    def test_failed_state_includes_error(self):
        """Setting FAILED state should include error message."""
        manager = ServerStateManager()
        manager.set_startup_state(
            StartupState.FAILED, "Failed to load", "Connection timeout"
        )

        assert manager.startup_state == StartupState.FAILED
        assert manager.startup_error == "Connection timeout"
        assert manager.models_ready is False
