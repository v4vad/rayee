# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Files

- **PLAN.md** - Development roadmap with phases, tasks, and architecture details. Check this for current progress and next steps.
- **README.md** - Public project description and requirements.

## Project Overview

Rayee is a local voice-to-text transcription app for macOS. It uses a two-component architecture:
- **Swift/SwiftUI frontend** (`swift/`) - Native macOS menu bar app handling UI, hotkeys, and auto-paste
- **Python backend** (`python/`) - AI transcription engine using Faster-Whisper and MLX-Whisper

The Swift app communicates with the Python server via local HTTP/Unix socket. All processing happens locally—no cloud services.

## Architecture

```
Swift App (UI layer)          Python Server (AI layer)
├── Global hotkey listening   ├── Audio recording (sounddevice)
├── Menu bar + status window  ├── Transcription (faster-whisper, mlx-whisper)
├── Auto-paste via a11y APIs  ├── Voice activity detection (silero-vad)
└── Settings management       └── Custom vocabulary handling
```

## Commands

### Python Development
```bash
# Set up virtual environment
cd python && python3 -m venv venv && source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run the server
python run_server.py
```

### Swift Development
```bash
# Open in Xcode
open swift/Rayee/Rayee.xcodeproj

# Build from command line
xcodebuild -project swift/Rayee/Rayee.xcodeproj -scheme Rayee build
```

## Key Dependencies

**Python:**
- `faster-whisper` - Primary transcription engine
- `mlx-whisper` - Apple Silicon optimized alternative
- `sounddevice` - Audio capture
- `silero-vad` - Voice activity detection
- `fastapi` or `flask` - Local API server

**Swift:**
- SwiftUI for interface
- Accessibility APIs for auto-paste
- Carbon/CGEvent for global hotkeys

## User Context

The project owner is not a developer. Explanations should be in plain language, avoiding technical jargon. When suggesting solutions, explain what each step does and why.

## Git Commits

Do NOT include "Co-Authored-By: Claude" or any mention of Claude in git commit messages.
