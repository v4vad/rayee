# Python Server — Rayee

FastAPI server running on a Unix domain socket. Handles AI inference: speech-to-text (Faster-Whisper) and text transformation (MLX Llama).

## File Map

| File | Purpose |
|------|---------|
| `server.py` | FastAPI app, all HTTP endpoints |
| `startup.py` | Server lifecycle: parallel model loading, executor pools, uvicorn |
| `state.py` | Thread-safe state machine (IDLE/RECORDING/TRANSCRIBING) + startup state |
| `transcribe.py` | `Transcriber` class wrapping Faster-Whisper |
| `models.py` | `ModelManager` + model registry (9 Whisper models), download/delete |
| `server_helpers.py` | Shared utilities: `read_wav_file()`, `transcribe_audio()`, Pydantic models |
| `vad.py` | `VoiceActivityDetector` (Silero VAD) + `SmartRecorder` (auto-stop on silence) |
| `audio.py` | Low-level audio recording with sounddevice (legacy, Swift records now) |
| `vocabulary.py` | Custom vocabulary storage (`~/.rayee/vocabulary.json`), cached prompt |
| `transform.py` | `TextTransformer` — validation, prompt building, output cleaning |
| `transform_prompts.py` | System/user prompt templates for 5 transform types |
| `transform_routes.py` | FastAPI router for `/transform`, `/transform_stream`, model management |
| `mlx_model.py` | `MLXModelManager` — Llama model lifecycle, generate, stream, auto-unload |

## Endpoints

### Transcription
| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/transcribe_raw` | Raw Float32 PCM bytes | `{text, status}` |
| POST | `/transcribe_file` | `{audio_path}` | `{text, status}` |
| POST | `/transcribe_upload` | `{audio_path}` | `{text, status}` (non-blocking) |
| POST | `/transcribe` | `{silence_duration}` | `{text, status}` (Python records) |

### Transforms
| Method | Path | Body | Response |
|--------|------|------|----------|
| POST | `/transform` | `{text, transformation_type}` | `{original_text, transformed_text, ...}` |
| POST | `/transform_stream` | `{text, transformation_type}` | Streamed plain text (token-by-token) |
| POST | `/transform/warmup` | — | `{status}` |
| GET | `/transform/status` | — | `{model_downloaded, model_loaded, ...}` |
| POST | `/transform/download` | — | `{status}` |
| GET | `/transform/download_status` | — | `{status, error}` |

### Models
| Method | Path | Response |
|--------|------|----------|
| GET | `/models` | List of models with status |
| POST | `/model` | Switch active model |
| POST | `/models/download/{name}` | Start download |
| GET | `/models/download_status/{name}` | Download progress |
| DELETE | `/models/{name}` | Delete model files |

### Status & Settings
| Method | Path | Response |
|--------|------|----------|
| GET | `/health` | `{status: "ok"}` |
| GET | `/status` | `{status: "idle/recording/transcribing"}` |
| GET | `/startup_status` | `{state, message, error}` |
| GET/POST | `/settings` | `{beam_size}` |
| GET/POST/DELETE | `/vocabulary` | `{words, count}` |

## Startup Sequence

1. `run_server()` in `startup.py` starts uvicorn on `~/.rayee/server.sock`
2. `on_startup()` fires `preload_models()` in a background thread
3. VAD and Whisper models load in **parallel** threads
4. State transitions: `NOT_STARTED → DOWNLOADING_VAD/DOWNLOADING_WHISPER → READY`
5. Three thread pools: `audio_executor(1)`, `upload_executor(1)`, `transform_executor(1)`

## Whisper Models

9 models available (defined in `models.py`):

| Model | Size | Category |
|-------|------|----------|
| tiny, base, small, medium | 75MB–1.5GB | Standard (multilingual) |
| large-v3, large-v3-turbo | 1.6–3GB | Standard (highest quality) |
| distil-small.en, distil-medium.en, distil-large-v3 | 330MB–1.4GB | Distil (English-only, faster) |

Default: `small`. Models from HuggingFace (`Systran/faster-whisper-*`).

## Transform LLM

- Model: `mlx-community/Llama-3.2-1B-Instruct-4bit` (~800MB)
- Auto-unloads after 30 seconds of inactivity to free RAM
- 5 transform types: grammar, bullets, rephrase, formal, casual
- Prompts defined in `transform_prompts.py`
- Output cleaned of LLM artifacts (wrapping quotes, "Here is..." preambles) via pre-compiled regex

## Key Patterns

- **Thread safety**: `state_manager` uses locks for state transitions; `transcription_lock` prevents concurrent Whisper access across executors
- **Streaming**: `mlx_model.stream_generate()` yields tokens; `transform_routes.py` bridges sync generator to async `StreamingResponse` via `queue.Queue`
- **Model lifecycle**: Lazy loading with auto-unload. Single background checker thread (not per-call timers)
- **Vocabulary**: JSON at `~/.rayee/vocabulary.json`, prompt string cached and invalidated on change

## Development

```bash
cd python && source venv/bin/activate
python -c "from rayee.startup import run_server; run_server()"
```

Pre-commit hooks enforce `black` formatting and `isort` import sorting.
