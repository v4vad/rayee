# Swift App — Rayee

macOS menu bar app built with SwiftUI. Handles recording, UI, hotkeys, history, and communicates with the Python server over a Unix socket.

## File Map

### Core
| File | Purpose |
|------|---------|
| `RayeeApp.swift` | App entry point, menu bar setup, window management |
| `AppState.swift` | Central state machine — observes all subsystems, drives UI |
| `Config.swift` | All constants: audio settings, timeouts, UI dimensions |
| `AppLogger.swift` | Structured logging with categories |

### Recording Pipeline
| File | Purpose |
|------|---------|
| `AudioRecorder.swift` | AVAudioEngine recording, RMS-based VAD, adaptive calibration, saves WAV |
| `TranscriptionCoordinator.swift` | Orchestrates: record → send to server → save history → auto-paste |
| `AudioLevelMonitor.swift` | Circular buffer of RMS levels for waveform visualization |
| `AudioFeedback.swift` | Start/stop/error sounds |
| `AudioFileConverter.swift` | Converts uploaded audio files to 16kHz mono WAV |

### Server Communication
| File | Purpose |
|------|---------|
| `PythonBridge.swift` | Raw Unix socket HTTP client — all server calls go through here |
| `UnixSocketProtocol.swift` | URLProtocol adapter for URLSession-based calls |
| `ServerManager.swift` | Launches/monitors/restarts the bundled Python server process |
| `HealthMonitor.swift` | Derives server online status from ServerManager + socket checks |

### UI — Recording Panel
| File | Purpose |
|------|---------|
| `RecordingPanelView.swift` | Floating panel content: recording/transcribing/result states |
| `RecordingPanelController.swift` | NSWindow management for the floating panel |
| `PanelButtonStyles.swift` | Pill-shaped button styles |
| `StatusIndicator.swift` | Colored dot indicator |

### UI — Menu Bar
| File | Purpose |
|------|---------|
| `MenuBarController.swift` | Menu bar icon and dropdown |
| `SimpleMenuView.swift` | The dropdown menu content |

### UI — Settings
| File | Purpose |
|------|---------|
| `SettingsView.swift` | Tab container for settings |
| `GeneralSettingsTab.swift` | Hotkey, silence, fast mode, adaptive VAD toggle |
| `ModelsSettingsTab.swift` | Whisper model picker with download/delete |
| `TransformationsSettingsTab.swift` | Transform toggle, LLM model status, type picker |
| `HotkeyPickerView.swift` | Hotkey recording UI |

### UI — Transforms
| File | Purpose |
|------|---------|
| `TransformationState.swift` | Published state for transform lifecycle + streaming text |
| `TransformationBar.swift` | Row of transform buttons below transcribed text |
| `TransformationButton.swift` | Individual transform button |
| `TransformationPreviewView.swift` | Live streaming preview + before/after comparison |
| `TransformAPITypes.swift` | Codable types for transform API requests/responses |

### UI — History & Uploads
| File | Purpose |
|------|---------|
| `HistoryView.swift` | Paginated history list with debounced search |
| `HistoryManager.swift` | SQLite storage with pagination (WAL, FULLMUTEX) |
| `TranscriptionRecord.swift` | Data model for a transcription entry |
| `UploadsView.swift` | Upload history list |
| `UploadManager.swift` | File upload → convert → transcribe flow |
| `UploadHistoryManager.swift` | In-memory upload history |
| `UploadRecord.swift` | Data model for an upload entry |
| `UploadRow.swift` | Single upload list row |

### Other
| File | Purpose |
|------|---------|
| `SettingsManager.swift` | UserDefaults wrapper for all settings |
| `HotkeyManager.swift` | Global hotkey via CGEvent tap |
| `PasteManager.swift` | Auto-paste via Accessibility API |
| `PasteTargetDetector.swift` | Detects if a text field is focused |
| `FasterWhisperManager.swift` | Model download/delete via Python server |
| `ModelRow.swift` | Reusable model list row component |
| `UpdateManager.swift` | Sparkle auto-update integration |
| `SetupGuideView.swift` | First-launch setup checklist |

## Audio Format

Everywhere in the app: **16kHz, mono, Float32 PCM**. `AudioRecorder` converts from the mic's native format using `AVAudioConverter`.

## Key Patterns

- **Singletons**: `AppState.shared`, `SettingsManager.shared`, `HistoryManager.shared`, `HealthMonitor.shared`, `ServerManager.shared`
- **Combine**: AppState observes child publishers (`$isRecording`, `$isTranscribing`, `$isServerOnline`)
- **PythonBridge**: Raw Unix socket HTTP — bypasses URLSession to avoid VPN/WARP interference. Each request creates a new socket connection.
- **Streaming**: `/transform_stream` uses chunked response reading — `rawSocketStreamingRequest` reads body incrementally and calls `onToken` callback

## Recording Flow Detail

1. `AppState.startTranscription()` → `TranscriptionCoordinator.startTranscription()`
2. Creates `AudioRecorder(silenceDuration:, timeoutEnabled:, adaptiveVADEnabled:)`
3. Adaptive VAD: first 200ms measures ambient RMS, sets threshold to `max(avgRMS * 1.5, 0.005)`
4. Audio tap processes 100ms chunks, computes RMS, detects speech
5. On silence timeout: `stopRecording()` → saves WAV + passes `audioBuffer` as `[Float]`
6. `transcribeRecording()` sends raw Float32 bytes to `/transcribe_raw` (falls back to WAV path)
7. Result → save to history, auto-paste if enabled, show in panel
