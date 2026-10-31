# Swift App — Rayee

macOS menu bar app built with SwiftUI. No server. How a dictation flows and the rules each part must keep: `docs/how-it-works.md`.

## Where things live

**Dictation flow**
- `TranscriptionCoordinator` runs one dictation: record → transcribe → clean up → deliver
- `AppState` is the shared state all views read; `DictationDelivery` keeps dictations in order (pure logic)
- `HotkeyManager` (global hotkey, CGEvent tap), `HotkeyPickerView` (choosing it)
- `AudioRecorder` (mic, speech detection, silence auto-stop), `AudioLevelMonitor` (waveform levels), `AudioFeedback` (start/stop sounds)
- `WhisperKitManager` (speech to text), `WhisperKitModelManager` (speech model catalog, downloads, recommended model)
- `LiveTranscriber` (Apple recognizer preview), `LiveTranscript` (draft vs settled words), `LivePreviewLanguages` (language list and downloads)
- `MLXTransformManager` (Smart Dictation prompt, Qwen models, model choice), `AppleTransformEngine` (Apple Intelligence), `TransformationState`
- `PasteTargetDetector` (is there a text field?), `PasteManager` (paste and clipboard restore)
- `HistoryManager` (SQLite), `TranscriptionRecord`

**Recorder (the notch / capsule)**
- `RecorderController` (the window), `RecorderState` (states, heights, Esc and click rules; pure), `RecorderView` (what it shows)
- `NotchGeometry` (position and size; pure), `NotchShape` (the outline and its smoothed corners)

**Settings, menu, setup**
- `SettingsView` (sidebar) with `GeneralSettingsTab`, `RecordingSettingsTab`, `SmartDictationSettingsTab`, `ModelsSettingsTab` + `ModelRow` (Speech Model), `VocabularySettingsTab` (Dictionary), `HistoryView`, `AboutSettingsTab`
- `SettingsManager` (all settings, UserDefaults), `Config` (fixed numbers: timeouts, sizes, limits)
- `SimpleMenuView` (menu-bar menu), `SystemStatus` (what's blocking Rayee and where to fix it), `OnboardingView` (5-step setup)
- `RayeeApp` (entry point), `UpdateManager` (Sparkle, install when idle), `AppLogger` (Xcode console only)

Files marked "pure" have no AppKit, so they're where unit tests live (`RayeeTests/`).
