# Rayee

Local voice-to-text transcription app for macOS. Two-process architecture: Swift frontend + Python backend communicating over a Unix domain socket at `~/.rayee/server.sock`.

## Project Structure

```
rayee/
├── swift/Rayee/          # macOS app (SwiftUI, menu bar)
│   └── Rayee/            # Source files — see swift/Rayee/Rayee/CLAUDE.md
├── python/rayee/         # AI server (FastAPI, Whisper, MLX) — see python/CLAUDE.md
├── ROADMAP.md            # Blocked/future optimizations
├── appcast.xml           # Sparkle auto-update feed
└── publish_release.sh    # Build + sign DMG script
```

## Architecture

```
┌─────────────────────────┐     Unix Socket      ┌──────────────────────────┐
│     Swift App           │  ←───────────────→    │    Python Server         │
│                         │   ~/.rayee/server.sock│                          │
│  AudioRecorder          │                       │  FastAPI + Uvicorn       │
│  TranscriptionCoord.    │   POST /transcribe_raw│  Faster-Whisper (STT)    │
│  AppState               │   POST /transform_*   │  MLX Llama 3.2 (LLM)    │
│  HistoryManager (SQLite)│   GET  /health        │  Silero VAD              │
│  HotkeyManager          │   GET  /models        │  Vocabulary manager      │
│  PasteManager           │                       │                          │
└─────────────────────────┘                       └──────────────────────────┘
```

## Data Flow: Recording → Transcription

1. User presses hotkey (Option+Space) → `HotkeyManager` → `AppState.startTranscription()`
2. `TranscriptionCoordinator` creates `AudioRecorder` (16kHz mono Float32 via AVAudioEngine)
3. Swift-side RMS VAD detects speech start/end (optional adaptive calibration)
4. On stop: raw PCM bytes sent directly to Python via `/transcribe_raw` (no WAV file round-trip)
5. Python runs Faster-Whisper → returns text
6. Text saved to SQLite history, optionally auto-pasted via Accessibility API

## Data Flow: Text Transform

1. User clicks transform button (Grammar/Bullets/Rephrase/Formal/Casual)
2. Swift calls `POST /transform_stream` — tokens stream back word-by-word
3. `TransformationPreviewView` shows text building up live
4. Python runs MLX Llama 3.2 1B (4-bit) with chat template prompts

## Key Files

| Purpose | File |
|---------|------|
| App entry point | `swift/Rayee/Rayee/RayeeApp.swift` |
| Central state | `swift/Rayee/Rayee/AppState.swift` |
| Audio recording | `swift/Rayee/Rayee/AudioRecorder.swift` |
| Server communication | `swift/Rayee/Rayee/PythonBridge.swift` |
| Transcription flow | `swift/Rayee/Rayee/TranscriptionCoordinator.swift` |
| Python API server | `python/rayee/server.py` |
| Whisper transcription | `python/rayee/transcribe.py` |
| LLM transforms | `python/rayee/transform.py` + `mlx_model.py` |
| Settings | `swift/Rayee/Rayee/SettingsManager.swift` |
| History (SQLite) | `swift/Rayee/Rayee/HistoryManager.swift` |

## Development Setup

```bash
# Python server (run in one terminal)
cd python && source venv/bin/activate
python -c "from rayee.startup import run_server; run_server()"

# Swift app (run from Xcode)
open swift/Rayee/Rayee.xcodeproj   # Cmd+R to build and run
```

The Python server must be running for transcription and transforms. In production, the server is bundled inside the .app and started automatically by `ServerManager`.

## Build & Release

Use the `/publish-release` skill — it handles version bump, DMG build, EdDSA signing, appcast update, and GitHub release.

## Conventions

- Swift: no tabs, 4-space indent, SwiftUI for all views
- Python: black + isort formatting enforced by pre-commit hooks
- All user settings stored in UserDefaults via `SettingsManager`
- History stored in SQLite at `~/.rayee/history.db` (WAL mode, FULLMUTEX)
- Audio format everywhere: 16kHz, mono, Float32 PCM
- Unix socket path: `~/.rayee/server.sock`
