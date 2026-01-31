# Swift Component - Rayee macOS App

This folder contains the native macOS menu bar application.

## What This Code Does

The Swift app handles everything the user sees and interacts with:
- **Menu bar icon** that shows current status
- **Global hotkey** (Option+Space) to start recording from any app
- **Auto-paste** - automatically types transcribed text where your cursor is
- **Settings** - configure hotkey, model, vocabulary, sounds
- **History** - saves and searches past transcriptions

The app talks to the Python server to do the actual transcription work.

## File Overview

| File | Purpose |
|------|---------|
| `RayeeApp.swift` | Main app entry point - sets up the menu bar |
| `AppState.swift` | Central state management - the "brain" of the app |
| `MenuBarView.swift` | The dropdown menu when you click the icon |
| `StatusIndicator.swift` | Animated dots showing current status |
| `PythonBridge.swift` | HTTP client that talks to the Python server |
| `HotkeyManager.swift` | Listens for global keyboard shortcuts |
| `PasteManager.swift` | Types text into other apps via accessibility |
| `SettingsManager.swift` | Saves/loads user preferences |
| `SettingsView.swift` | Settings window UI |
| `HistoryManager.swift` | SQLite database for past transcriptions |
| `HistoryView.swift` | History tab UI with search |
| `AudioFeedback.swift` | Plays sounds for start/stop/error |
| `ServerManager.swift` | Manages the bundled Python server |

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

## Data Storage

| Data | Location |
|------|----------|
| Settings | UserDefaults (managed by macOS) |
| History | `~/.rayee/history.db` (SQLite) |
| Vocabulary | `~/.rayee/vocabulary.json` (via Python) |

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

The `PythonBridge` class sends HTTP requests to `http://localhost:8765`:
- Checks server health every 10 seconds
- Sends transcription requests with silence duration setting
- Handles errors gracefully (shows user-friendly messages)
