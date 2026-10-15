# Swift App — Rayee

macOS menu bar app built with SwiftUI. Handles recording, on-device transcription (WhisperKit), on-device text transforms (MLX), UI, hotkeys and history. No server.

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
| `AudioRecorder.swift` | AVAudioEngine recording, RMS-based VAD, adaptive calibration; hands [Float] samples to the coordinator |
| `TranscriptionCoordinator.swift` | Orchestrates: record → WhisperKit transcribe → save history → auto-paste |
| `AudioLevelMonitor.swift` | Circular buffer of RMS levels for waveform visualization |
| `AudioFeedback.swift` | Start/stop/error sounds |

### AI — Transcription & Transforms
| File | Purpose |
|------|---------|
| `WhisperKitManager.swift` | CoreML Whisper wrapper — load model, transcribe `[Float]`, vocabulary |
| `WhisperKitModelManager.swift` | Model list/download/delete via WhisperKit APIs + FileManager |
| `MLXTransformManager.swift` | MLX Llama 3.2 1B wrapper — streaming transforms, 30s auto-unload |

### UI — Recording Panel
| File | Purpose |
|------|---------|
| `RecordingPanelView.swift` | Floating panel content: recording/transcribing/result states |
| `RecordingPanelController.swift` | NSWindow management for the floating panel |
| `PanelButtonStyles.swift` | Pill-shaped button styles |

### UI — Menu Bar
| File | Purpose |
|------|---------|
| `SimpleMenuView.swift` | Menu bar dropdown (MenuBarExtra content) |

### UI — Settings
| File | Purpose |
|------|---------|
| `SettingsView.swift` | Tab container for settings |
| `GeneralSettingsTab.swift` | Hotkey, auto-paste, sounds, timeout, silence, adaptive VAD |
| `ModelsSettingsTab.swift` | Whisper model picker with download/delete |
| `TransformationsSettingsTab.swift` | Transform toggle, LLM model status, type picker |
| `HotkeyPickerView.swift` | Hotkey recording UI |
| `VocabularySettingsTab.swift` | Custom vocabulary list |

### UI — Transforms
| File | Purpose |
|------|---------|
| `TransformationState.swift` | Published state for transform lifecycle + streaming text |
| `TransformationPreviewView.swift` | Live streaming preview + before/after comparison |

### UI — History
| File | Purpose |
|------|---------|
| `HistoryView.swift` | Paginated history list with debounced search |
| `HistoryManager.swift` | SQLite storage with pagination (WAL, FULLMUTEX) |
| `TranscriptionRecord.swift` | Data model for a transcription entry |

### Other
| File | Purpose |
|------|---------|
| `SettingsManager.swift` | UserDefaults wrapper for all settings |
| `HotkeyManager.swift` | Global hotkey via CGEvent tap |
| `PasteManager.swift` | Auto-paste via Accessibility API |
| `PasteTargetDetector.swift` | Detects if a text field is focused |
| `ModelRow.swift` | Reusable model list row component |
| `UpdateManager.swift` | Sparkle auto-update integration |
| `SetupGuideView.swift` | First-launch setup checklist |

## Audio Format

Everywhere in the app: **16kHz, mono, Float32 PCM**. `AudioRecorder` converts from the mic's native format using `AVAudioConverter`.

## Key Patterns

- **Singletons**: `AppState.shared`, `SettingsManager.shared`, `HistoryManager.shared`, `WhisperKitManager.shared`, `MLXTransformManager.shared`
- **Combine**: AppState observes child publishers (`$isRecording`, `$isTranscribing`, `$isWhisperReady`)
- **Streaming**: `MLXTransformManager.streamTransform()` yields tokens via `AsyncStream<Generation>` — `onToken` callback updates `TransformationState` on each chunk
- **MLX auto-unload**: `MLXTransformManager` schedules a 30s `Timer` after each generation; idle model is released to free GPU memory

## Recording Flow Detail

1. `AppState.startTranscription()` → `TranscriptionCoordinator.startTranscription()`
2. Creates `AudioRecorder(silenceDuration:, timeoutEnabled:, adaptiveVADEnabled:)`
3. Adaptive VAD: first 200ms measures ambient RMS, sets threshold to `max(avgRMS * 1.5, 0.005)`
4. Audio tap processes 100ms chunks, computes RMS, detects speech
5. On silence timeout: `stopRecording()` → passes `audioBuffer` as `[Float]`
6. `WhisperKitManager.transcribe(audioBuffer:vocabulary:)` runs CoreML Whisper on-device
7. Result → save to history, auto-paste if enabled, show in panel
