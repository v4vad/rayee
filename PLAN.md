# Rayee - Local Voice Transcription App

**Project Location:** `/Users/karthikvadlapatla/claude/rayee`

---

## CURRENT STATUS (January 16, 2026)

### What's Done
- Phase 0: Project setup complete
- Phase 1: Python transcription engine complete and tested
- Phase 2: Python server complete and tested

### Next Step
- **Phase 3:** Build the Swift/macOS menu bar app

### How to Run the Server
```bash
cd /Users/karthikvadlapatla/claude/rayee/python
source venv/bin/activate
python run_server.py
```
Server runs on `http://localhost:8765`

### Files Created
```
python/
├── venv/                    # Python virtual environment (Python 3.11)
├── requirements.txt         # Dependencies list
├── run_server.py           # Server entry point
├── test_rayee.py           # Main test script
├── test_mic.py             # Microphone diagnostic
├── diagnose_audio.py       # Real-time audio/VAD diagnostic
└── rayee/
    ├── __init__.py
    ├── audio.py            # Microphone recording
    ├── transcribe.py       # Speech-to-text using Whisper
    ├── models.py           # AI model management
    ├── vad.py              # Voice activity detection (auto-stop)
    ├── server.py           # FastAPI server with endpoints
    └── vocabulary.py       # Custom word management
```

---

## What Rayee Does
A voice-to-text app that runs entirely on your Mac. Press a hotkey, speak, and the text appears wherever you're typing.

---

## Requirements Summary

### Core Features
1. **Runs locally** - All processing on your Mac, no internet needed, fully private
2. **Visual UI** - Shows "Listening..." and "Transcribing..." status
3. **Auto-paste** - Automatically types text into your current app
4. **Custom vocabulary** - Add names, terms, jargon for better recognition
5. **Multiple models** - Faster-Whisper + MLX-Whisper (can add more later)

### Extra Features
6. **Global hotkey** - Trigger recording from any app (e.g., Option+Space)
7. **History** - Save and search past transcriptions
8. **Voice activity detection** - Auto-stops when you stop talking

---

## Technical Approach

### Architecture: Swift + Python

```
┌─────────────────────────────────────────┐
│           Swift (The Mac App)           │
│  • Native macOS interface               │
│  • Menu bar icon + status window        │
│  • Global hotkey listening              │
│  • Auto-paste via accessibility APIs    │
│  • Settings UI                          │
└─────────────────┬───────────────────────┘
                  │ communicates via
                  ▼
┌─────────────────────────────────────────┐
│         Python (The AI Engine)          │
│  • Audio recording (sounddevice)        │
│  • Transcription (faster-whisper, mlx)  │
│  • Voice activity detection (silero)    │
│  • Custom vocabulary handling           │
│  • Model management                     │
└─────────────────────────────────────────┘
```

### Models
- **Faster-Whisper** (small, medium, large) - Fast and accurate
- **MLX-Whisper** - Optimized for Apple Silicon (M1/M2/M3/M4)

---

## Build Phases

### Phase 0: Project Setup ✅
**Goal:** Create project structure and version control

- [x] Create project folder at `/Users/karthikvadlapatla/claude/rayee`
- [x] Initialize git repository
- [x] Create folder structure (python/, swift/)
- [x] Copy this plan into the project as `PLAN.md`
- [x] Create initial README.md
- [x] Make first commit

### Phase 1: Python Foundation ✅
**Goal:** Get transcription working from command line

- [x] Set up Python environment
- [x] Install faster-whisper and dependencies
- [x] Create basic audio recording script
- [x] Create transcription script
- [x] Test: Record → Transcribe → Print text
- [x] Add voice activity detection (auto-stop)

**Files created:**
- `python/rayee/audio.py` - Recording functions
- `python/rayee/transcribe.py` - Transcription functions
- `python/rayee/vad.py` - Voice activity detection
- `python/rayee/models.py` - Model loading/switching
- `python/test_rayee.py` - Test script

### Phase 2: Python Server ✅
**Goal:** Python runs as a background service the Swift app can talk to

- [x] Create local HTTP server (FastAPI on localhost:8765)
- [x] Add endpoints: /transcribe, /status, /health
- [x] Add model switching endpoints: /models, /model
- [x] Add custom vocabulary support: /vocabulary
- [x] Test: All endpoints verified working

**Files created:**
- `python/rayee/server.py` - FastAPI server with all endpoints
- `python/rayee/vocabulary.py` - Custom word handling (saves to ~/.rayee/vocabulary.json)
- `python/run_server.py` - Entry point script

### Phase 3: Swift App (Basic)
**Goal:** Native Mac app that talks to Python

- [ ] Create new Xcode project (SwiftUI)
- [ ] Create menu bar app with icon
- [ ] Add status window (Listening/Transcribing/Ready)
- [ ] Connect to Python server
- [ ] Test: Click menu → Python records → Text appears in window

**Files to create:**
- `swift/Rayee/` - Xcode project folder
- `swift/Rayee/RayeeApp.swift` - Main app entry
- `swift/Rayee/MenuBarView.swift` - Menu bar interface
- `swift/Rayee/StatusWindow.swift` - Recording status UI
- `swift/Rayee/PythonBridge.swift` - Communication with Python

### Phase 4: Swift App (Features)
**Goal:** Add hotkey, auto-paste, settings

- [ ] Register global keyboard shortcut
- [ ] Implement auto-paste via Accessibility APIs
- [ ] Request necessary macOS permissions
- [ ] Add settings window (hotkey, model selection, vocabulary)
- [ ] Test: Hotkey → Record → Text pastes into any app

**Files to create:**
- `swift/Rayee/HotkeyManager.swift` - Global shortcut handling
- `swift/Rayee/PasteManager.swift` - Auto-paste functionality
- `swift/Rayee/SettingsView.swift` - Settings interface

### Phase 5: History & Polish
**Goal:** Save transcriptions, polish the experience

- [ ] Add SQLite database for history
- [ ] Create history view in app
- [ ] Add search functionality
- [ ] Add audio feedback sounds (start/stop beeps)
- [ ] Polish UI and fix bugs
- [ ] Package app for easy installation

**Files to create:**
- `swift/Rayee/HistoryManager.swift` - Database handling
- `swift/Rayee/HistoryView.swift` - History UI
- `python/rayee/database.py` - Python-side history storage

---

## Project Structure

```
rayee/
├── python/                    # Python AI engine
│   ├── rayee/
│   │   ├── __init__.py
│   │   ├── audio.py          # Recording
│   │   ├── transcribe.py     # AI transcription
│   │   ├── vad.py            # Voice detection
│   │   ├── models.py         # Model management
│   │   ├── vocabulary.py     # Custom words
│   │   ├── server.py         # Local API
│   │   └── database.py       # History storage
│   ├── requirements.txt
│   └── run_server.py         # Entry point
│
├── swift/                     # Swift Mac app
│   └── Rayee/
│       ├── Rayee.xcodeproj
│       └── Rayee/
│           ├── RayeeApp.swift
│           ├── MenuBarView.swift
│           ├── StatusWindow.swift
│           ├── SettingsView.swift
│           ├── HistoryView.swift
│           ├── PythonBridge.swift
│           ├── HotkeyManager.swift
│           └── PasteManager.swift
│
├── PLAN.md                    # This file
└── README.md
```

---

## What You'll Need

### Software to Install
1. **Python 3.10+** - For the AI engine
2. **Xcode** - For building the Swift app (free from App Store)
3. **Homebrew** - Package manager for Mac (we'll install this)

### Python Packages
- `faster-whisper` - Fast transcription
- `mlx-whisper` - Apple Silicon optimized
- `sounddevice` - Audio recording
- `numpy` - Audio processing
- `silero-vad` - Voice activity detection
- `flask` or `fastapi` - Local server

### macOS Permissions Needed
- Microphone access
- Accessibility access (for auto-paste)

---

## Development Tools & Recommendations

This section documents helpful tools for building Rayee more efficiently when working with Claude Code.

### MCPs (Model Context Protocol Servers)

MCPs are plugins that give Claude Code extra capabilities. Here are the ones that will help with this project:

| MCP | What It Does | When You'll Need It |
|-----|--------------|---------------------|
| **Xcode MCP** | Lets Claude interact with Xcode projects directly - build, manage files, check errors | Phase 3-4 (Swift app development) |
| **GitHub MCP** | Manages issues, pull requests, and releases from within Claude | Throughout project for tracking |
| **SQLite MCP** | Reads and writes to SQLite databases | Phase 5 (transcription history) |
| **Fetch MCP** | Makes HTTP requests to test API endpoints | Phase 2-3 (testing the Python server) |

**How to install MCPs:** Go to Claude Code settings and add the MCP server URLs. See [Claude Code MCP documentation](https://docs.anthropic.com/claude-code/mcp) for details.

### Built-in Claude Code Agents

Claude Code has specialized agents you can use without installing anything:

- **Explore Agent** - Use when you need to understand how existing code works (e.g., "How does the audio recording work?")
- **Plan Agent** - Use when designing new features before writing code
- **Bash Agent** - Use for running terminal commands and scripts

### Recommended Editor Extensions

If you're editing code manually outside of Claude Code:

**For VS Code:**
- **Python** - Syntax highlighting and debugging for Python files
- **Swift** - Syntax highlighting for Swift files
- **REST Client** - Test API endpoints directly from VS Code

### External Tools

These standalone apps can help during development:

| Tool | What It Does | When It's Useful |
|------|--------------|------------------|
| **Postman** or **Insomnia** | Visual API testing tools | Testing Python server endpoints |
| **SF Symbols** (free from Apple) | Browse macOS system icons | Choosing icons for the menu bar app |
| **Proxyman** | HTTP debugging proxy for Mac | Debugging Swift ↔ Python communication |

---

## Verification / Testing

After each phase, we'll test:

1. **Phase 1:** Run Python script, speak, see text printed
2. **Phase 2:** Send HTTP request, get transcription back
3. **Phase 3:** Click menu bar, see status change, see text in window
4. **Phase 4:** Press hotkey in any app, speak, text appears where cursor is
5. **Phase 5:** Check history shows past transcriptions, search works

---

## Notes

- We start with Python because it's where the AI models work best
- Swift handles the "Mac app" experience (looks native, feels native)
- The two talk to each other through a local connection (never goes to internet)
- Custom vocabulary works by giving the AI hints about expected words
- Can add more models later without changing the Swift app
