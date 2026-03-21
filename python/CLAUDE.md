# Python Component - Rayee Transcription Engine

This folder contains the AI-powered backend for Rayee.

## What This Code Does

The Python server handles all the "smart" parts:
- **Recording audio** from your microphone
- **Detecting when you stop talking** (voice activity detection)
- **Converting speech to text** using AI models (Whisper)
- **Transforming text** — fix grammar, rephrase, format (using Llama 3.2 via MLX)
- **Managing custom vocabulary** for better recognition

The Swift app talks to this server over HTTP via a Unix domain socket at `~/.rayee/server.sock` (avoids interfering with VPNs like Cloudflare WARP).

## File Overview

| File | Purpose |
|------|---------|
| `server.py` | Web server with API endpoints - the main entry point |
| `audio.py` | Records from your microphone using sounddevice |
| `transcribe.py` | Sends audio to Whisper AI and gets text back |
| `vad.py` | Voice Activity Detection - knows when you stop talking |
| `models.py` | Manages which AI model is loaded (tiny, small, medium, etc.) |
| `vocabulary.py` | Stores custom words to help recognition |
| `transform.py` | Text transformer - applies grammar fixes, rephrasing, etc. |
| `transform_prompts.py` | Prompt templates for each transformation type |
| `transform_routes.py` | FastAPI router for `/transform` endpoints |
| `mlx_model.py` | Loads/unloads the Llama 3.2 1B model via MLX |
| `server_helpers.py` | Pydantic models for all request/response types |
| `startup.py` | Server startup/shutdown hooks and thread pools |

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
| `/transcribe_file` | POST | Transcribe an uploaded audio file |
| `/models` | GET | List available AI models |
| `/models/download/{name}` | POST | Download a specific Whisper model |
| `/vocabulary` | GET/POST | Manage custom words |
| `/transform` | POST | Transform text (grammar, bullets, rephrase, etc.) |
| `/transform/status` | GET | Check if the LLM model is loaded/downloaded |
| `/transform/download` | POST | Download the transform model (Llama 3.2) |
| `/transform/download_status` | GET | Check download progress |

## Common Tasks

### Run the server
```bash
cd python && source venv/bin/activate && python run_server.py
```

### Test an endpoint
```bash
curl --unix-socket ~/.rayee/server.sock http://localhost/health
curl --unix-socket ~/.rayee/server.sock http://localhost/status
```

### Check if server is responding
```bash
curl -s http://localhost:8765/health | grep -q "ok" && echo "Server OK" || echo "Server not running"
```

### Thread Pools
Different operations run in separate thread pools to avoid blocking:
- `audio_executor` — recording and transcription
- `upload_executor` — file upload transcription
- `transform_executor` — text transformations (LLM inference)

### MLX Model Management
The transform model (Llama 3.2 1B, 4-bit quantized) is:
- Lazy-loaded on first transformation request
- Auto-unloaded after 30 seconds of inactivity to free ~800MB RAM
- Cached locally in `~/.rayee/llm_models/`

## Dependencies

- `faster-whisper` - The AI model that converts speech to text
- `sounddevice` - Records audio from your microphone
- `torch` - Required for voice activity detection
- `fastapi` + `uvicorn` - Web server framework
- `mlx` + `mlx-lm` - Apple Silicon LLM inference for text transformations

## Data Storage

- Custom vocabulary: `~/.rayee/vocabulary.json`
- LLM model cache: `~/.rayee/llm_models/`
