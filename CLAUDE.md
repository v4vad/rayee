# Rayee

Local voice-to-text transcription app for macOS. Pure native Swift — no Python, no server process.

## Project Structure

```
rayee/
├── swift/Rayee/          # macOS app (SwiftUI, menu bar)
│   └── Rayee/            # Source files — see swift/Rayee/Rayee/CLAUDE.md
├── ROADMAP.md            # Completed work + future ideas
├── appcast.xml           # Sparkle auto-update feed
└── publish_release.sh    # Build + sign DMG script
```

## Architecture

Everything runs inside the Swift app — no server, no sockets, no Python.

```
┌──────────────────────────────────────────────────────────┐
│                      Swift App                           │
│                                                          │
│  AudioRecorder (AVAudioEngine, 16kHz Float32)            │
│  WhisperKitManager — CoreML transcription (on-device)    │
│  MLXTransformManager — Llama 3.2 1B 4-bit via MLX       │
│  TranscriptionCoordinator — orchestrates record→text     │
│  AppState — central state machine                        │
│  HistoryManager — SQLite at ~/.rayee/history.db          │
│  HotkeyManager — global hotkey via CGEvent tap           │
│  PasteManager — auto-paste via Accessibility API         │
└──────────────────────────────────────────────────────────┘
```

## Data Flow: Recording → Transcription

1. User presses hotkey (Option+Space) → `HotkeyManager` → `AppState.startTranscription()`
2. `TranscriptionCoordinator` creates `AudioRecorder` (16kHz mono Float32 via AVAudioEngine)
3. Swift-side RMS VAD detects speech start/end (optional adaptive calibration)
4. On stop: `[Float]` audio buffer passed directly to `WhisperKitManager.transcribe()`
5. WhisperKit runs CoreML Whisper on-device → returns text
6. Text saved to SQLite history, optionally auto-pasted via Accessibility API

## Data Flow: Text Transform

1. User clicks transform button (Grammar/Bullets/Rephrase/Formal/Casual)
2. `MLXTransformManager.streamTransform()` runs Llama 3.2 1B (4-bit) via MLX Swift
3. `TransformationPreviewView` shows tokens streaming in live
4. Model auto-unloads after 30s idle to free memory

## Key Files

| Purpose | File |
|---------|------|
| App entry point | `swift/Rayee/Rayee/RayeeApp.swift` |
| Central state | `swift/Rayee/Rayee/AppState.swift` |
| Audio recording | `swift/Rayee/Rayee/AudioRecorder.swift` |
| Transcription flow | `swift/Rayee/Rayee/TranscriptionCoordinator.swift` |
| WhisperKit wrapper | `swift/Rayee/Rayee/WhisperKitManager.swift` |
| MLX LLM wrapper | `swift/Rayee/Rayee/MLXTransformManager.swift` |
| Settings | `swift/Rayee/Rayee/SettingsManager.swift` |
| History (SQLite) | `swift/Rayee/Rayee/HistoryManager.swift` |

## Development Setup

```bash
# Swift app only — open in Xcode and run
open swift/Rayee/Rayee.xcodeproj   # Cmd+R to build and run
```

No server to start. WhisperKit and the MLX model download on first use.

## Build & Release

Use the `/publish-release` skill — it handles version bump, DMG build, EdDSA signing, appcast update, and GitHub release.

## Conventions

- Swift: no tabs, 4-space indent, SwiftUI for all views
- All user settings stored in UserDefaults via `SettingsManager`
- History stored in SQLite at `~/.rayee/history.db` (WAL mode, FULLMUTEX)
- Audio format everywhere: 16kHz, mono, Float32 PCM
