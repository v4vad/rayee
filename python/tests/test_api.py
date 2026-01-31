"""
Tests for API endpoints.

Run with: cd python && pytest tests/ -v
"""

import pytest
from fastapi.testclient import TestClient
from rayee.server import app
from rayee.state import StartupState, state_manager


@pytest.fixture
def client():
    """Create a test client for the FastAPI app."""
    return TestClient(app)


@pytest.fixture(autouse=True)
def reset_state():
    """Reset server state before each test."""
    from rayee.state import ServerState

    state_manager.set_state(ServerState.IDLE)
    yield


class TestHealthEndpoint:
    """Test the /health endpoint."""

    def test_health_returns_ok(self, client):
        """Health endpoint should return ok status."""
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


class TestStatusEndpoint:
    """Test the /status endpoint."""

    def test_status_returns_idle(self, client):
        """Status should be idle initially."""
        response = client.get("/status")
        assert response.status_code == 200
        assert response.json()["status"] == "idle"


class TestStartupStatusEndpoint:
    """Test the /startup_status endpoint."""

    def test_startup_status_returns_state(self, client):
        """Startup status should return current state."""
        response = client.get("/startup_status")
        assert response.status_code == 200
        data = response.json()
        assert "state" in data
        assert "message" in data


class TestTranscribeEndpoint:
    """Test the /transcribe endpoint."""

    def test_transcribe_returns_503_when_models_not_ready(self, client):
        """Transcribe should return 503 when models aren't loaded."""
        # Ensure models are not ready
        state_manager.models_ready = False
        state_manager.startup_state = StartupState.NOT_STARTED

        response = client.post("/transcribe")
        assert response.status_code == 503
        assert "still loading" in response.json()["detail"].lower()


class TestTranscribeFileEndpoint:
    """Test the /transcribe_file endpoint."""

    def test_transcribe_file_returns_400_for_missing_file(self, client):
        """Should return 400 when file doesn't exist."""
        # Set models as ready so we get past that check
        state_manager.models_ready = True

        response = client.post(
            "/transcribe_file", json={"audio_path": "/nonexistent/path/audio.wav"}
        )
        assert response.status_code == 400
        assert "not found" in response.json()["detail"].lower()

        # Reset
        state_manager.models_ready = False


class TestVocabularyEndpoints:
    """Test vocabulary management endpoints."""

    def test_get_vocabulary_returns_list(self, client):
        """Get vocabulary should return words list."""
        response = client.get("/vocabulary")
        assert response.status_code == 200
        data = response.json()
        assert "words" in data
        assert "count" in data
        assert isinstance(data["words"], list)

    def test_add_empty_word_returns_400(self, client):
        """Adding empty word should return 400."""
        response = client.post("/vocabulary", json={"word": ""})
        assert response.status_code == 400
        assert "empty" in response.json()["detail"].lower()

    def test_add_whitespace_word_returns_400(self, client):
        """Adding whitespace-only word should return 400."""
        response = client.post("/vocabulary", json={"word": "   "})
        assert response.status_code == 400
