# Rayee - Local Voice Transcription App

**Project Location:** `/Users/karthikvadlapatla/claude/rayee`

---

## CURRENT STATUS (March 21, 2026)

### What's Done
- Phase 0: Project setup complete
- Phase 1: Python transcription engine complete and tested
- Phase 2: Python server complete and tested
- Phase 3: Swift/macOS menu bar app complete
- Phase 4: Global hotkey, auto-paste, and settings complete
- Phase 5: History & polish complete
- Phase 6: Text transformations (Grammar, Bullets, Rephrase, Formal, Casual) using Llama 3.2 via MLX
- Phase 7: Setup guide with hotkey picker and system status checklist

### Next Step
- **Project complete!** All core features + text transformations implemented.

### How to Run the Server
```bash
cd /Users/karthikvadlapatla/claude/rayee/python
source venv/bin/activate
python run_server.py
```
Server communicates via Unix socket at `~/.rayee/server.sock`

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
    ├── vocabulary.py       # Custom word management
    ├── transform.py        # Text transformer using MLX
    ├── transform_prompts.py # Prompt templates for transformations
    ├── transform_routes.py  # FastAPI router for /transform endpoints
    └── mlx_model.py        # MLX model manager (Llama 3.2 1B)
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
5. **Multiple models** - Faster-Whisper (tiny, small, medium, large)

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
│  • Transcription (faster-whisper)        │
│  • Voice activity detection (silero)    │
│  • Custom vocabulary handling           │
│  • Model management                     │
└─────────────────────────────────────────┘
```

### Models
- **Faster-Whisper** (small, medium, large) - Fast and accurate

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

### Phase 3: Swift App (Basic) ✅
**Goal:** Native Mac app that talks to Python

- [x] Create new Xcode project (SwiftUI)
- [x] Create menu bar app with icon
- [x] Add status window (Listening/Transcribing/Ready)
- [x] Connect to Python server
- [x] Test: Click menu → Python records → Text appears in window

**Files created:**
- `swift/Rayee/` - Xcode project folder
- `swift/Rayee/RayeeApp.swift` - Main app entry
- `swift/Rayee/MenuBarView.swift` - Menu bar interface
- `swift/Rayee/StatusIndicator.swift` - Animated status display
- `swift/Rayee/PythonBridge.swift` - Communication with Python
- `swift/Rayee/AppState.swift` - Central state management

### Phase 4: Swift App (Features) ✅
**Goal:** Add hotkey, auto-paste, settings

- [x] Register global keyboard shortcut (Option+Space default)
- [x] Implement auto-paste via Accessibility APIs
- [x] Request necessary macOS permissions (accessibility)
- [x] Add settings window (hotkey, model selection, vocabulary, auto-paste toggle)
- [x] Test: Hotkey → Record → Text pastes into any app

**Files created:**
- `swift/Rayee/HotkeyManager.swift` - Global shortcut handling using CGEvent tap
- `swift/Rayee/PasteManager.swift` - Auto-paste via clipboard + Cmd+V simulation
- `swift/Rayee/SettingsManager.swift` - UserDefaults-based settings persistence
- `swift/Rayee/SettingsView.swift` - Settings interface with tabs

### Phase 5: History & Polish ✅
**Goal:** Save transcriptions, polish the experience

- [x] Add SQLite database for history (Swift-side, stored in ~/.rayee/history.db)
- [x] Create history view in app (Settings → History tab)
- [x] Add search functionality (search bar in History tab)
- [x] Add audio feedback sounds (start/stop/error beeps using system sounds)
- [x] Add sounds toggle in Settings (General tab → "Play sounds")
- [ ] Package app for easy installation (optional future step)

**Files created:**
- `swift/Rayee/Rayee/TranscriptionRecord.swift` - Data model for history entries
- `swift/Rayee/Rayee/HistoryManager.swift` - SQLite database handling
- `swift/Rayee/Rayee/HistoryView.swift` - History UI with search, copy, delete
- `swift/Rayee/Rayee/AudioFeedback.swift` - Sound playback using NSSound

### Phase 6: Text Transformations ✅
**Goal:** Transform transcribed text locally using Llama 3.2 via MLX

- [x] Python backend: MLX model manager, prompt templates, transformer class
- [x] Python API: POST /transform, GET /transform/status, POST /transform/download
- [x] Swift UI: TransformationBar with 5 pill-shaped buttons (Cmd+1-5)
- [x] Swift UI: TransformationPreviewView with before/after comparison
- [x] Settings tab for managing transform model and enabled types
- [x] History integration: stores original + transformed text, shows toggle
- [x] Error handling: user-friendly messages for server/model/timeout errors
- [x] Cancel button during transformation loading state

**New Python files:**
- `python/rayee/mlx_model.py` - MLX model loading/unloading with 30s timeout
- `python/rayee/transform_prompts.py` - 5 prompt templates
- `python/rayee/transform.py` - TextTransformer with validation and cleaning
- `python/rayee/transform_routes.py` - FastAPI router for /transform endpoints

**New Swift files:**
- `swift/Rayee/Rayee/TransformationState.swift` - UI state for transform flow
- `swift/Rayee/Rayee/TransformationButton.swift` - Pill button with loading/success states
- `swift/Rayee/Rayee/TransformationBar.swift` - Horizontal row with Cmd+1-5 shortcuts
- `swift/Rayee/Rayee/TransformationPreviewView.swift` - Original vs transformed preview
- `swift/Rayee/Rayee/TransformationsSettingsTab.swift` - Model + type management
- `swift/Rayee/Rayee/TransformAPITypes.swift` - Codable response types

### Phase 7: Setup Guide ✅
**Goal:** First-launch experience and system status

- [x] Setup guide checklist (server, mic, accessibility, whisper model, transform model)
- [x] Hotkey picker with key recorder and conflict detection
- [x] Auto-opens on first launch, accessible from "System Status..." menu
- [x] "Done" button marks setup as complete

**New Swift files:**
- `swift/Rayee/Rayee/SetupGuideView.swift` - Checklist with auto-refresh
- `swift/Rayee/Rayee/HotkeyPickerView.swift` - Key combination recorder

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
│   │   └── server.py         # Local API
│   ├── requirements.txt
│   └── run_server.py         # Entry point
│
├── swift/                     # Swift Mac app
│   └── Rayee/
│       ├── Rayee.xcodeproj
│       └── Rayee/
│           ├── RayeeApp.swift
│           ├── AppState.swift
│           ├── MenuBarView.swift
│           ├── StatusIndicator.swift
│           ├── SettingsView.swift
│           ├── SettingsManager.swift
│           ├── HistoryView.swift
│           ├── HistoryManager.swift
│           ├── TranscriptionRecord.swift
│           ├── AudioFeedback.swift
│           ├── PythonBridge.swift
│           ├── HotkeyManager.swift
│           ├── PasteManager.swift
│           ├── TransformationState.swift
│           ├── TransformationButton.swift
│           ├── TransformationBar.swift
│           ├── TransformationPreviewView.swift
│           ├── TransformationsSettingsTab.swift
│           ├── TransformAPITypes.swift
│           ├── SetupGuideView.swift
│           └── HotkeyPickerView.swift
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
