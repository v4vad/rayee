# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Files

- **PLAN.md** - Development roadmap with phases, tasks, and architecture details. Check this for current progress and next steps.
- **README.md** - Public project description and requirements.

## Project Overview

Rayee is a local voice-to-text transcription app for macOS. It uses a two-component architecture:
- **Swift/SwiftUI frontend** (`swift/`) - Native macOS menu bar app handling UI, hotkeys, and auto-paste
- **Python backend** (`python/`) - AI transcription engine using Faster-Whisper

The Swift app communicates with the Python server via local HTTP/Unix socket. All processing happens locally—no cloud services.

## Architecture

```
Swift App (UI layer)          Python Server (AI layer)
├── Global hotkey listening   ├── Audio recording (sounddevice)
├── Menu bar + status window  ├── Transcription (faster-whisper)
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

## Code Quality Rules

Follow these rules when writing or modifying code:

### File Size Limits
- **Maximum 300 lines per file** - If a file exceeds this, split it into smaller focused files
- This keeps code readable and maintainable

### Single Responsibility
- Each file should do **one main thing**
- If you find yourself adding "and" when describing what a file does, it probably needs splitting
- Examples:
  - `PythonBridge.swift` → handles server communication
  - `HealthMonitor.swift` → monitors server health
  - `TranscriptionCoordinator.swift` → coordinates recording flow

### No Duplicate Code
- If you copy-paste code, extract it into a helper function
- Look for patterns that repeat more than twice

### Constants in Config
- Magic numbers (timeouts, retry counts, thresholds) go in `Config.swift` (Swift) or a constants file (Python)
- Don't scatter hardcoded values throughout the code

### Code Review Checklist
Before finishing any changes, verify:
- [ ] Files under 300 lines?
- [ ] No duplicate code?
- [ ] Constants centralized?
- [ ] Existing tests still pass?

## Pre-commit Hooks

This project uses pre-commit hooks to catch issues before commits:

```bash
# Install pre-commit (one time)
pip install pre-commit
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

The hooks will:
- Format Python code with `black`
- Sort Python imports with `isort`
- Check for large files, merge conflicts, and debug statements
- Warn if files exceed 300 lines

## Running Tests

### Python Tests
```bash
cd python
source venv/bin/activate
pytest tests/ -v
```

### Swift Build Verification
```bash
xcodebuild -project swift/Rayee/Rayee.xcodeproj -scheme Rayee build
```

## Troubleshooting

### Server won't start
**Symptom:** Running `python run_server.py` fails or hangs

**Check these:**
1. Is the virtual environment activated? Run `source venv/bin/activate` first
2. Are dependencies installed? Run `pip install -r requirements.txt`
3. Is port 8765 already in use? Run `lsof -i :8765` to check
4. Kill any existing server: `pkill -f run_server.py`

### App says "Server not running"
**Symptom:** The Swift app shows server offline

**Check these:**
1. Is the Python server actually running? Open Terminal and check
2. Test the server directly: `curl http://localhost:8765/health`
3. Check if firewall is blocking localhost connections

### Microphone not working
**Symptom:** Recording starts but no audio is captured

**Check these:**
1. System Preferences → Security & Privacy → Microphone → ensure Terminal/Python has access
2. Test microphone in another app first
3. Run `python test_mic.py` to diagnose

### Hotkey not working
**Symptom:** Pressing Option+Space does nothing

**Check these:**
1. System Preferences → Security & Privacy → Accessibility → ensure Rayee is enabled
2. Another app might be using the same hotkey
3. Try changing the hotkey in Settings

### Auto-paste not working
**Symptom:** Text transcribes but doesn't paste

**Check these:**
1. Accessibility permission must be granted (same as hotkey)
2. Check if "Auto-paste" is enabled in Settings
3. Some apps block simulated keyboard input

## Agent Delegation

Use subagents for cost-effective model selection:

| Task Type | Agent | Model | Examples |
|-----------|-------|-------|----------|
| Quick commands | `quick-executor` | Haiku | `git status`, `python run_server.py`, `pytest`, `pre-commit run` |
| Coding work | `coder` | Sonnet | Writing Swift/Python code, fixing bugs, adding features |
| Deep thinking | `architect` | Opus | Architecture decisions, complex debugging, code review |

## Testing & Verification

### Quick health check
```bash
# Check if server responds
curl http://localhost:8765/health

# Check server status
curl http://localhost:8765/status
```

### Test transcription manually
```bash
# Start recording (speak, then wait for it to finish)
curl -X POST http://localhost:8765/transcribe
```

### Verify Python environment
```bash
cd python
source venv/bin/activate
python --version  # Should be 3.10+
pip list | grep -E "faster-whisper|sounddevice|fastapi"
```

### Verify Swift build
```bash
xcodebuild -project swift/Rayee/Rayee.xcodeproj -scheme Rayee build
```

### Test full flow
1. Start Python server: `cd python && source venv/bin/activate && python run_server.py`
2. Run the Swift app from Xcode or build folder
3. Click the menu bar icon → Start Recording
4. Speak something → Text should appear
