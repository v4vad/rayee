# Python Component - Rayee Transcription Engine

This folder contains the AI-powered backend for Rayee.

## What This Code Does

The Python server handles all the "smart" parts:
- **Recording audio** from your microphone
- **Detecting when you stop talking** (voice activity detection)
- **Converting speech to text** using AI models (Whisper)
- **Managing custom vocabulary** for better recognition

The Swift app talks to this server over HTTP on `localhost:8765`.

## File Overview

| File | Purpose |
|------|---------|
| `server.py` | Web server with API endpoints - the main entry point |
| `audio.py` | Records from your microphone using sounddevice |
| `transcribe.py` | Sends audio to Whisper AI and gets text back |
| `vad.py` | Voice Activity Detection - knows when you stop talking |
| `models.py` | Manages which AI model is loaded (tiny, small, medium, etc.) |
| `vocabulary.py` | Stores custom words to help recognition |

## Key Patterns

### State Machine
The server uses a simple state machine to prevent conflicts:
- `idle` → `recording` → `transcribing` → `idle`
- Only one operation can happen at a time

### Thread Safety
Audio operations run in a dedicated thread pool (`_audio_executor`) because:
- macOS has specific thread requirements for audio
- Keeps the server responsive during long recordings

### Error Handling
All endpoints return consistent JSON:
- Success: `{"status": "success", "data": ...}`
- Error: `{"error": "message", "detail": "..."}`

## API Endpoints

| Endpoint | Method | What It Does |
|----------|--------|--------------|
| `/health` | GET | Check if server is running |
| `/status` | GET | Get current state (idle/recording/transcribing) |
| `/transcribe` | POST | Record and convert speech to text |
| `/models` | GET | List available AI models |
| `/model` | POST | Switch to a different model |
| `/vocabulary` | GET/POST | Manage custom words |

## Common Tasks

### Run the server
```bash
cd python && source venv/bin/activate && python run_server.py
```

### Test an endpoint
```bash
curl http://localhost:8765/health
curl http://localhost:8765/status
```

### Check if server is responding
```bash
curl -s http://localhost:8765/health | grep -q "ok" && echo "Server OK" || echo "Server not running"
```

## Dependencies

- `faster-whisper` - The AI model that converts speech to text
- `sounddevice` - Records audio from your microphone
- `torch` - Required for voice activity detection
- `fastapi` + `uvicorn` - Web server framework

## Data Storage

Custom vocabulary is saved to: `~/.rayee/vocabulary.json`
