# Swift Component - Rayee macOS App

This folder contains the native macOS menu bar application.

## What This Code Does

The Swift app handles everything the user sees and interacts with:
- **Menu bar icon** that shows current status
- **Global hotkey** (Option+Space) to start recording from any app
- **Auto-paste** - automatically types transcribed text where your cursor is
- **Text transformations** - fix grammar, rephrase, format as bullets, change tone
- **Setup guide** - first-launch checklist showing what's ready and what needs attention
- **Settings** - configure hotkey, model, vocabulary, sounds, transformations
- **History** - saves and searches past transcriptions with transformation tracking

The app talks to the Python server to do the actual transcription work.

## File Overview

### Core
| File | Purpose |
|------|---------|
| `RayeeApp.swift` | Main app entry point - sets up the menu bar and windows |
| `AppState.swift` | Central state management - the "brain" of the app |
| `Config.swift` | All constants (timeouts, sizes, URLs) in one place |
| `PythonBridge.swift` | HTTP client that talks to the Python server |
| `UnixSocketProtocol.swift` | Routes HTTP requests through Unix domain socket (avoids VPN conflicts) |
| `ServerManager.swift` | Manages the bundled Python server |
| `HealthMonitor.swift` | Checks server health on a timer |

### UI
| File | Purpose |
|------|---------|
| `MenuBarController.swift` | NSStatusItem-based menu bar icon and dropdown (Bartender-compatible) |
| `StatusIndicator.swift` | Animated dots showing current status |
| `RecordingPanelView.swift` | Floating panel during recording/transcription |
| `RecordingPanelController.swift` | Manages the floating panel window |
| `PanelButtonStyles.swift` | Shared button styles for the floating panel |
| `SettingsView.swift` | Settings window with tabs |
| `GeneralSettingsTab.swift` | General settings (hotkey, model, sounds) |

### Text Transformations
| File | Purpose |
|------|---------|
| `TransformationState.swift` | UI state for the transform flow |
| `TransformationBar.swift` | Row of transform buttons (Cmd+1-5 shortcuts) |
| `TransformationButton.swift` | Pill-shaped button with loading/success states |
| `TransformationPreviewView.swift` | Before/after text comparison with error display |
| `TransformationsSettingsTab.swift` | Settings for model management and enabled types |
| `TransformAPITypes.swift` | Codable types for transform API responses |

### Setup & Onboarding
| File | Purpose |
|------|---------|
| `SetupGuideView.swift` | First-launch checklist (server, permissions, models) |
| `HotkeyPickerView.swift` | Key recorder with conflict detection |

### Services
| File | Purpose |
|------|---------|
| `HotkeyManager.swift` | Listens for global keyboard shortcuts |
| `PasteManager.swift` | Types text into other apps via accessibility |
| `SettingsManager.swift` | Saves/loads user preferences |
| `TranscriptionCoordinator.swift` | Coordinates the record → transcribe flow |
| `AudioRecorder.swift` | Records audio from the microphone |
| `AudioLevelMonitor.swift` | Monitors audio levels for the waveform |
| `AudioFeedback.swift` | Plays sounds for start/stop/error |

### History
| File | Purpose |
|------|---------|
| `HistoryManager.swift` | SQLite database for past transcriptions |
| `HistoryView.swift` | History tab UI with search, copy, delete |
| `TranscriptionRecord.swift` | Data model with transformation tracking |

## Key Patterns

### @Published and ObservableObject
SwiftUI uses reactive updates. When a `@Published` property changes, the UI automatically refreshes:
```swift
@Published var status: AppStatus = .ready  // UI updates when this changes
```

### Singleton Managers
Shared functionality uses the singleton pattern:
```swift
let settings = SettingsManager.shared
let hotkeyManager = HotkeyManager.shared
```

### Task and async/await
Network calls to Python use Swift's modern concurrency:
```swift
Task { @MainActor in
    let text = try await pythonBridge.transcribe()
}
```

### Accessibility APIs
Auto-paste and global hotkeys require macOS accessibility permission. The app:
1. Checks if permission is granted
2. Prompts the user if not
3. Uses CGEvent for keyboard simulation

## Status Flow

```
ready → recording → transcribing → ready
  ↓         ↓            ↓
error ←←←←←←←←←←←←←←←←←←←
```

## Transformation Flow

```
Transcription result → [Transform button / Cmd+1-5]
  → Loading spinner → Preview (original vs transformed)
  → "Use This" (accept) or "Original" (revert)
  → Error display if server/model/timeout issue
```

## Data Storage

| Data | Location |
|------|----------|
| Settings | UserDefaults (managed by macOS) |
| History | `~/.rayee/history.db` (SQLite, includes transformation data) |
| Vocabulary | `~/.rayee/vocabulary.json` (via Python) |
| LLM models | `~/.rayee/llm_models/` (via Python) |

## macOS Permissions Required

1. **Microphone** - for recording (Python handles this)
2. **Accessibility** - for global hotkey and auto-paste

## Common Tasks

### Build the app
```bash
xcodebuild -project swift/Rayee/Rayee.xcodeproj -scheme Rayee build
```

### Open in Xcode
```bash
open swift/Rayee/Rayee.xcodeproj
```

## Communication with Python

The `PythonBridge` class sends HTTP requests through a Unix domain socket at `~/.rayee/server.sock`:
- Checks server health every 10 seconds
- Sends transcription requests with silence duration setting
- Sends text transformation requests (grammar, bullets, rephrase, etc.)
- Manages transform model downloads and status checks
- Handles errors gracefully (shows user-friendly messages)
