# Native Swift Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Python server entirely with native Swift — WhisperKit for transcription and mlx-swift-lm for LLM transforms — producing a single self-contained .app with instant startup and no Python dependency.

**Architecture:** `WhisperKitManager` wraps the WhisperKit v1.0.0 CoreML transcription API and holds the loaded model in memory for the app's lifetime. `MLXTransformManager` wraps mlx-swift-lm's AsyncStream-based generation API with auto-unload after 30s idle. `WhisperKitModelManager` replaces `FasterWhisperManager` for model download/list/delete. The `PythonBridge`, `ServerManager`, `HealthMonitor`, and `UnixSocketProtocol` files are deleted in the final phase.

**Tech Stack:**
- `argmax-oss-swift` v1.0.0 — `https://github.com/argmaxinc/argmax-oss-swift` — import `WhisperKit`
- `mlx-swift-lm` v3.31.3 — `https://github.com/ml-explore/mlx-swift-lm` — import `MLXLLM`, `MLXLMCommon`
- XCTest — added as new test target `RayeeTests`

**Key facts verified before writing this plan:**
- `argmax-oss-swift` v1.0.0 vendored `swift-transformers` internally → no external dependency
- `mlx-swift-lm` has zero `swift-transformers` dependency → no SPM conflict
- WhisperKit API: `transcribe(audioArray: [Float], decodeOptions: DecodingOptions?, callback: TranscriptionCallback?) async throws -> [TranscriptionResult]`
- WhisperKit vocabulary: `DecodingOptions.promptTokens: [Int]?` (must pre-tokenize strings)
- WhisperKit model delete: no public API — use `FileManager` to remove cached files
- mlx-swift-lm streaming: `AsyncStream<Generation>` from `generate(input:parameters:context:)`
- Llama 3.2 1B 4-bit is a first-class built-in: `ModelConfiguration.llama3_2_1B_4bit` or `ModelConfiguration(id: "mlx-community/Llama-3.2-1B-Instruct-4bit")`

---

## File Map

### New files (create)
| File | Purpose |
|------|---------|
| `swift/Rayee/Rayee/WhisperKitManager.swift` | WhisperKit wrapper: load model, transcribe `[Float]`, vocabulary |
| `swift/Rayee/Rayee/WhisperKitModelManager.swift` | Model list/download/delete via WhisperKit APIs + FileManager |
| `swift/Rayee/Rayee/MLXTransformManager.swift` | mlx-swift-lm wrapper: streaming transforms, auto-unload |
| `swift/Rayee/RayeeTests/WhisperKitManagerTests.swift` | Unit tests for prompt building and vocabulary tokenization |
| `swift/Rayee/RayeeTests/MLXTransformManagerTests.swift` | Unit tests for prompt construction |

### Files modified
| File | What changes |
|------|-------------|
| `swift/Rayee/Rayee/TranscriptionCoordinator.swift` | Replace `PythonBridge` transcription with `WhisperKitManager` |
| `swift/Rayee/Rayee/AppState.swift` | Remove server deps, remove `isServerOnline`, remove Python warmup |
| `swift/Rayee/Rayee/SettingsManager.swift` | Replace `TranscriptionModel` enum with string-based WhisperKit model IDs |
| `swift/Rayee/Rayee/Config.swift` | Remove `serverBaseURL`, `transcriptionTimeout`, `regularTimeout`; add WhisperKit model directory |
| `swift/Rayee/Rayee/RayeeApp.swift` | Remove `ServerManager.shared.start/stop()` |
| `swift/Rayee/Rayee/ModelsSettingsTab.swift` | Replace `FasterWhisperManager` with `WhisperKitModelManager` |
| `swift/Rayee/Rayee/TransformationsSettingsTab.swift` | Replace Python status calls with `MLXTransformManager` state |
| `swift/Rayee/Rayee/SetupGuideView.swift` | Remove Python server status item |
| `swift/Rayee/Rayee/UploadManager.swift` | Replace `pythonBridge.transcribeUpload()` with `WhisperKitManager` |

### Files deleted (Phase 3)
- `swift/Rayee/Rayee/PythonBridge.swift`
- `swift/Rayee/Rayee/UnixSocketProtocol.swift`
- `swift/Rayee/Rayee/ServerManager.swift`
- `swift/Rayee/Rayee/HealthMonitor.swift`
- `swift/Rayee/Rayee/FasterWhisperManager.swift`
- `python/` directory (entire Python server)

---

## Phase 1: WhisperKit STT

---

### Task 1: Add SPM packages and create test target

> **⚠ HUMAN-DRIVEN — Do this BEFORE dispatching any subagents.**
> This task cannot be done by a subagent. Xcode's SPM integration writes binary-format data into `project.pbxproj` that is not reliably editable by hand. The human developer must do these steps directly in Xcode.

**Files:**
- Modify: `swift/Rayee/Rayee.xcodeproj` (via Xcode UI)

- [ ] **Step 1: Open Xcode project**

```bash
open swift/Rayee/Rayee.xcodeproj
```

- [ ] **Step 2: Add argmax-oss-swift package**

In Xcode: File → Add Package Dependencies → enter URL:
```
https://github.com/argmaxinc/argmax-oss-swift
```
Select version: `from: 1.0.0`.
Add product **WhisperKit** to target **Rayee**.

- [ ] **Step 3: Add mlx-swift-lm package**

In Xcode: File → Add Package Dependencies → enter URL:
```
https://github.com/ml-explore/mlx-swift-lm
```
Select version: `from: 3.31.3`.
Add products **MLXLLM** and **MLXLMCommon** to target **Rayee**.

- [ ] **Step 4: Create test target**

In Xcode: File → New → Target → macOS → Unit Testing Bundle.
Name it `RayeeTests`. Set host application to `Rayee`.

- [ ] **Step 5: Check deployment target**

`argmax-oss-swift` v1.0.0 uses Swift 6 concurrency. Open the Rayee target → Build Settings → search "macOS Deployment Target". If it says `13.0`, change it to `14.0` (Swift 6 strict concurrency warnings may fail on 13.0 since some APIs require 14+).

Also set the same `14.0` deployment target for the `RayeeTests` target.

- [ ] **Step 6: Verify build compiles**

```bash
cd swift/Rayee
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

If you see Swift 6 concurrency errors, add `SWIFT_STRICT_CONCURRENCY = complete` as a build setting override for now — subagents will fix actor isolation issues in later tasks.

- [ ] **Step 7: Commit**

```bash
git add swift/Rayee/Rayee.xcodeproj
git commit -m "feat: add argmax-oss-swift and mlx-swift-lm packages, create RayeeTests target, bump deployment target to macOS 14"
```

---

### Task 2: Create WhisperKitManager

**Files:**
- Create: `swift/Rayee/Rayee/WhisperKitManager.swift`
- Create: `swift/Rayee/RayeeTests/WhisperKitManagerTests.swift`

`WhisperKitManager` is a singleton that holds a loaded `WhisperKit` instance. The model loads once and persists. Vocabulary words are passed as `promptTokens` (pre-tokenized).

- [ ] **Step 1: Write failing test**

Create `swift/Rayee/RayeeTests/WhisperKitManagerTests.swift`:

```swift
import XCTest
@testable import Rayee

final class WhisperKitManagerTests: XCTestCase {

    func testBuildVocabularyPrompt() {
        let words = ["Karthik", "Rayee", "MLX"]
        let prompt = WhisperKitManager.buildVocabularyPrompt(from: words)
        XCTAssertEqual(prompt, "Karthik, Rayee, MLX")
    }

    func testBuildVocabularyPromptEmptyList() {
        let prompt = WhisperKitManager.buildVocabularyPrompt(from: [])
        XCTAssertNil(prompt)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd swift/Rayee
xcodebuild test -scheme RayeeTests -destination "platform=macOS" 2>&1 | grep -E "FAIL|error:|WhisperKitManager"
```
Expected: compile error — `WhisperKitManager` doesn't exist yet.

- [ ] **Step 3: Verify WhisperKit API before coding**

Before writing the implementation, confirm the exact constructor and transcribe signatures by checking the WhisperKit source. Run this from the worktree:

```bash
# Find the downloaded source (SPM caches it here)
find ~/Library/Developer/Xcode/DerivedData -name "WhisperKit.swift" -path "*/Sources/*" 2>/dev/null | head -3
# Or:
find ~/Library/Caches/org.swift.swiftpm -name "WhisperKit.swift" 2>/dev/null | head -3
```

Check the `WhisperKit` public init signature. It should be:
```swift
public init(model: String, ...) async throws
```
And the transcribe signature:
```swift
public func transcribe(audioArray: [Float], decodeOptions: DecodingOptions?, callback: TranscriptionCallback?) async throws -> [TranscriptionResult]
```
And tokenizer:
```swift
wk.tokenizer?.encode(text:) -> [Int]?   // or similar
```

If the tokenizer property name or encode method differs, adjust the implementation below accordingly before writing it. The `DecodingOptions` `promptTokens` parameter should be `[Int]?`.

- [ ] **Step 4: Create WhisperKitManager**

Create `swift/Rayee/Rayee/WhisperKitManager.swift`:

```swift
import Foundation
import WhisperKit

@MainActor
class WhisperKitManager: ObservableObject {
    static let shared = WhisperKitManager()

    @Published private(set) var isLoading = false
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?

    private var whisperKit: WhisperKit?
    private var currentModelName: String?

    private init() {}

    // MARK: - Model Loading

    func loadModel(_ modelName: String) async {
        guard modelName != currentModelName || whisperKit == nil else { return }
        isLoading = true
        loadError = nil

        do {
            whisperKit = try await WhisperKit(model: modelName)
            currentModelName = modelName
            isLoaded = true
            AppLogger.log("WhisperKit loaded: \(modelName)", category: "whisper")
        } catch {
            loadError = error.localizedDescription
            isLoaded = false
            AppLogger.log("WhisperKit load failed: \(error)", category: "whisper")
        }

        isLoading = false
    }

    // MARK: - Transcription

    func transcribe(audioBuffer: [Float], vocabulary: [String]) async throws -> String {
        guard let wk = whisperKit else {
            throw WhisperKitError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let prompt = Self.buildVocabularyPrompt(from: vocabulary),
           let tokens = try? wk.tokenizer?.encode(text: prompt) {
            options = DecodingOptions(promptTokens: tokens)
        }

        let results = try await wk.transcribe(audioArray: audioBuffer, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    static func buildVocabularyPrompt(from words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        return words.joined(separator: ", ")
    }
}

enum WhisperKitError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded. Please wait for initialization."
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd swift/Rayee
xcodebuild test -scheme RayeeTests -destination "platform=macOS" -only-testing:RayeeTests/WhisperKitManagerTests 2>&1 | grep -E "PASS|FAIL|error:"
```
Expected: `Test Suite 'WhisperKitManagerTests' passed`

- [ ] **Step 6: Commit**

```bash
git add swift/Rayee/Rayee/WhisperKitManager.swift swift/Rayee/RayeeTests/WhisperKitManagerTests.swift
git commit -m "feat: add WhisperKitManager wrapping WhisperKit transcription"
```

---

### Task 3: Create WhisperKitModelManager

**Files:**
- Create: `swift/Rayee/Rayee/WhisperKitModelManager.swift`

Replaces `FasterWhisperManager`. Uses `WhisperKit.fetchAvailableModels()` to list models and `ModelManager.downloadModels()` to download. Deletion uses `FileManager` to remove cached CoreML files.

WhisperKit caches models at `~/Library/Caches/huggingface/hub/` by default. The model folder is named after the model string (e.g., `openai_whisper-small`).

- [ ] **Step 1: Create WhisperKitModelManager**

Create `swift/Rayee/Rayee/WhisperKitModelManager.swift`:

```swift
import Foundation
import WhisperKit
import SwiftUI

struct WKModelInfo: Identifiable, Equatable {
    let id: String       // WhisperKit model name, e.g. "openai_whisper-small"
    var status: WKModelStatus
    var sizeMB: Int

    var displayName: String {
        id.replacingOccurrences(of: "openai_whisper-", with: "")
          .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
    }

    var formattedSize: String {
        sizeMB >= 1000
            ? String(format: "%.1f GB", Double(sizeMB) / 1000.0)
            : "\(sizeMB) MB"
    }
}

enum WKModelStatus: Equatable {
    case notDownloaded
    case downloading(fractionCompleted: Double)
    case ready
    case error(String)
}

@MainActor
class WhisperKitModelManager: ObservableObject {
    static let shared = WhisperKitModelManager()

    @Published var models: [WKModelInfo] = []
    @Published var selectedModelName: String = "openai_whisper-small"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        selectedModelName = UserDefaults.standard.string(forKey: "selectedWhisperKitModel")
            ?? "openai_whisper-small"
    }

    // MARK: - Model Listing

    func refreshModels() async {
        isLoading = true
        errorMessage = nil

        do {
            let available = try await WhisperKit.fetchAvailableModels()
            let downloaded = downloadedModelNames()
            models = available.map { name in
                WKModelInfo(
                    id: name,
                    status: downloaded.contains(name) ? .ready : .notDownloaded,
                    sizeMB: estimatedSizeMB(for: name)
                )
            }
        } catch {
            errorMessage = "Failed to load models: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Download

    func downloadModel(_ name: String) {
        guard downloadTasks[name] == nil else { return }

        updateStatus(name, .downloading(fractionCompleted: 0))

        downloadTasks[name] = Task {
            do {
                let wk = try await WhisperKit(model: name, download: true)
                _ = wk // triggers download
                updateStatus(name, .ready)
            } catch {
                updateStatus(name, .error(error.localizedDescription))
            }
            downloadTasks.removeValue(forKey: name)
        }
    }

    // MARK: - Selection

    func selectModel(_ name: String) {
        selectedModelName = name
        UserDefaults.standard.set(name, forKey: "selectedWhisperKitModel")
    }

    // MARK: - Delete

    func deleteModel(_ name: String) {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = cacheURL.appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots")

        do {
            let snapshots = try FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            for snapshot in snapshots {
                let modelFolder = snapshot.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: modelFolder.path) {
                    try FileManager.default.removeItem(at: modelFolder)
                }
            }
            updateStatus(name, .notDownloaded)
            if selectedModelName == name {
                selectModel("openai_whisper-small")
            }
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ name: String, _ status: WKModelStatus) {
        if let i = models.firstIndex(where: { $0.id == name }) {
            models[i].status = status
        }
    }

    private func downloadedModelNames() -> Set<String> {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let modelDir = cacheURL.appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots")
        guard let snapshots = try? FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var names = Set<String>()
        for snapshot in snapshots {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: snapshot.path) {
                contents.forEach { names.insert($0) }
            }
        }
        return names
    }

    private func estimatedSizeMB(for name: String) -> Int {
        // Approximate CoreML model sizes
        if name.contains("large-v3-turbo") { return 809 }
        if name.contains("large-v3") { return 1600 }
        if name.contains("distil-large") { return 756 }
        if name.contains("distil-medium") { return 394 }
        if name.contains("distil-small") { return 166 }
        if name.contains("medium") { return 793 }
        if name.contains("small") { return 244 }
        if name.contains("base") { return 145 }
        if name.contains("tiny") { return 75 }
        return 244
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd swift/Rayee
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add swift/Rayee/Rayee/WhisperKitModelManager.swift
git commit -m "feat: add WhisperKitModelManager for CoreML model list/download/delete"
```

---

### Task 4: Wire WhisperKit into TranscriptionCoordinator

**Files:**
- Modify: `swift/Rayee/Rayee/TranscriptionCoordinator.swift`

Replace `PythonBridge` with `WhisperKitManager`. The `transcribeRecording()` method now calls `WhisperKitManager.shared.transcribe()`. The WAV file fallback path is removed (not needed with native transcription).

- [ ] **Step 1: Update TranscriptionCoordinator**

Replace the entire `TranscriptionCoordinator.swift` with:

```swift
import Foundation
import Combine

enum TranscriptionResult {
    case success(text: String, didPaste: Bool)
    case cancelled
    case error(message: String)
}

class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false

    private let settings: SettingsManager
    private let historyManager: HistoryManager
    private let audioFeedback: AudioFeedback
    private let pasteManager: PasteManager

    private var audioRecorder: AudioRecorder?
    private var pendingAutoPaste = false

    var onTranscriptionComplete: ((TranscriptionResult) -> Void)?
    var onAudioLevelUpdate: ((Float) -> Void)?

    init(
        settings: SettingsManager = .shared,
        historyManager: HistoryManager = .shared,
        audioFeedback: AudioFeedback = .shared,
        pasteManager: PasteManager = .shared
    ) {
        self.settings = settings
        self.historyManager = historyManager
        self.audioFeedback = audioFeedback
        self.pasteManager = pasteManager
    }

    func startTranscription(autoPaste: Bool = false) {
        guard !isRecording && !isTranscribing else { return }
        pendingAutoPaste = autoPaste
        startRecording()
    }

    func stopRecording() {
        if isRecording { audioRecorder?.stopRecording() }
    }

    func cancel() {
        if isRecording {
            audioRecorder?.cancelRecording()
            audioRecorder = nil
            isRecording = false
            audioFeedback.playErrorSound()
        }
    }

    private func startRecording() {
        Task { @MainActor in
            let hasPermission = await AudioRecorder.requestMicrophonePermission()
            if !hasPermission {
                AppLogger.log("Microphone permission denied", category: "transcription")
            }
            self.beginRecordingSession()
        }
    }

    private func beginRecordingSession() {
        isRecording = true
        audioFeedback.playStartSound()

        audioRecorder = AudioRecorder(
            silenceDuration: settings.silenceDuration,
            timeoutEnabled: settings.timeoutEnabled,
            adaptiveVADEnabled: settings.adaptiveVADEnabled
        )

        audioRecorder?.onRecordingComplete = { [weak self] result in
            self?.handleRecordingComplete(result)
        }
        audioRecorder?.onAudioLevel = { [weak self] level in
            self?.onAudioLevelUpdate?(level)
        }

        do {
            try audioRecorder?.startRecording()
        } catch {
            handleRecordingError(error)
        }
    }

    private func handleRecordingComplete(_ result: Result<RecordingResult, AudioRecorderError>) {
        audioRecorder = nil
        isRecording = false

        switch result {
        case .success(let recordingResult):
            AppLogger.log("Recording complete: \(String(format: "%.1f", recordingResult.duration))s", category: "transcription")
            transcribeRecording(recordingResult)
        case .failure(let error):
            if case .noAudioRecorded = error {
                audioFeedback.playStopSound()
                onTranscriptionComplete?(.cancelled)
            } else {
                handleRecordingError(error)
            }
        }
    }

    private func handleRecordingError(_ error: Error) {
        isRecording = false
        audioRecorder = nil
        audioFeedback.playErrorSound()
        onTranscriptionComplete?(.error(message: error.localizedDescription))
    }

    private func transcribeRecording(_ result: RecordingResult) {
        isTranscribing = true
        AppLogger.log("Transcribing audio via WhisperKit...", category: "transcription")

        Task { @MainActor in
            do {
                let vocabulary = settings.vocabularyList
                let text = try await WhisperKitManager.shared.transcribe(
                    audioBuffer: result.audioData,
                    vocabulary: vocabulary
                )
                self.handleTranscriptionSuccess(text)
            } catch {
                self.handleTranscriptionError(error)
            }
        }
    }

    private func handleTranscriptionSuccess(_ text: String) {
        isTranscribing = false
        AppLogger.log("Transcription succeeded: \(text.prefix(80))", category: "transcription")
        audioFeedback.playStopSound()

        if !text.isEmpty {
            historyManager.saveTranscription(
                text: text,
                model: settings.selectedWhisperKitModel
            )
        }

        var didPaste = false
        if pendingAutoPaste && settings.autoPasteEnabled && !text.isEmpty {
            if PasteTargetDetector.hasValidPasteTarget() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Config.autoPasteDelay) {
                    self.pasteManager.pasteText(text)
                }
                didPaste = true
            }
        }

        onTranscriptionComplete?(.success(text: text, didPaste: didPaste))
    }

    private func handleTranscriptionError(_ error: Error) {
        isTranscribing = false
        AppLogger.log("Transcription failed: \(error.localizedDescription)", category: "transcription")
        audioFeedback.playErrorSound()
        onTranscriptionComplete?(.error(message: error.localizedDescription))
    }
}
```

Note: `result.audioData` is a `[Float]` — confirm the type in `RecordingResult`. If it's `Data`, convert with:
```swift
let floats = audioData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
```

- [ ] **Step 2: Add `selectedWhisperKitModel` to SettingsManager with UserDefaults migration**

Existing users have `selectedModel` stored as Faster-Whisper names like `"small"`, `"large-v3"`, etc. We need to migrate those to WhisperKit CoreML names on first launch.

In `swift/Rayee/Rayee/SettingsManager.swift`, add to the `SettingsKey` enum:
```swift
static let selectedWhisperKitModel = "selectedWhisperKitModel"
```

Add the migration map and computed property to `SettingsManager`:
```swift
// Maps old Faster-Whisper model names to WhisperKit CoreML names
private static let fwToWhisperKitNames: [String: String] = [
    "tiny": "openai_whisper-tiny",
    "base": "openai_whisper-base",
    "small": "openai_whisper-small",
    "medium": "openai_whisper-medium",
    "large-v3": "openai_whisper-large-v3",
    "large-v3-turbo": "openai_whisper-large-v3-turbo",
    "distil-small.en": "distil-whisper_distil-small.en",
    "distil-medium.en": "distil-whisper_distil-medium.en",
    "distil-large-v3": "distil-whisper_distil-large-v3"
]

var selectedWhisperKitModel: String {
    get {
        // Already migrated
        if let saved = UserDefaults.standard.string(forKey: SettingsKey.selectedWhisperKitModel) {
            return saved
        }
        // Migrate from old FasterWhisper name
        if let oldName = UserDefaults.standard.string(forKey: SettingsKey.selectedModel),
           let migrated = Self.fwToWhisperKitNames[oldName] {
            UserDefaults.standard.set(migrated, forKey: SettingsKey.selectedWhisperKitModel)
            return migrated
        }
        return "openai_whisper-small"
    }
    set { UserDefaults.standard.set(newValue, forKey: SettingsKey.selectedWhisperKitModel) }
}
```

- [ ] **Step 3: Build to verify it compiles**

```bash
cd swift/Rayee
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```
Fix any errors (type mismatches, missing properties). Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add swift/Rayee/Rayee/TranscriptionCoordinator.swift swift/Rayee/Rayee/SettingsManager.swift
git commit -m "feat: wire WhisperKit transcription into TranscriptionCoordinator"
```

---

### Task 5: Update AppState and RayeeApp for server-less operation

**Files:**
- Modify: `swift/Rayee/Rayee/AppState.swift`
- Modify: `swift/Rayee/Rayee/RayeeApp.swift`

Remove all server-related state. `isServerOnline` becomes irrelevant — replace with `isWhisperReady` based on `WhisperKitManager.isLoaded`. Load WhisperKit at startup instead of Python server.

- [ ] **Step 1: Update AppState**

In `swift/Rayee/Rayee/AppState.swift`:

**Remove** these properties:
```swift
@Published var isServerOnline: Bool = false
private let pythonBridge = PythonBridge()
private let healthMonitor = HealthMonitor.shared
let serverManager = ServerManager.shared
```

**Add** these properties:
```swift
@Published var isWhisperReady: Bool = false
@Published var isWhisperLoading: Bool = false
```

**Update** `AppStatus` enum — replace `startingServer` and `downloadingModels` with:
```swift
enum AppStatus: String {
    case loadingModels = "Loading AI models..."
    case ready = "Ready"
    case recording = "Listening..."
    case transcribing = "Transcribing..."
    case error = "Error"
}
```

**Replace** `setupBindings()` — remove the `healthMonitor.$isServerOnline` and `serverManager.$state` sinks. Add WhisperKitManager observation:
```swift
WhisperKitManager.shared.$isLoaded
    .receive(on: DispatchQueue.main)
    .sink { [weak self] loaded in
        self?.isWhisperReady = loaded
        if loaded && self?.status == .loadingModels {
            self?.status = .ready
        }
    }
    .store(in: &cancellables)

WhisperKitManager.shared.$isLoading
    .receive(on: DispatchQueue.main)
    .sink { [weak self] loading in
        self?.isWhisperLoading = loading
        if loading { self?.status = .loadingModels }
    }
    .store(in: &cancellables)
```

**Replace** `init()` — remove `healthMonitor.start()`:
```swift
init() {
    setupBindings()
    setupHotkey()
    startHotkeyListening()
    loadWhisperModel()
}
```

**Add** `loadWhisperModel()`:
```swift
func loadWhisperModel() {
    let modelName = SettingsManager.shared.selectedWhisperKitModel
    Task { await WhisperKitManager.shared.loadModel(modelName) }
}
```

**Remove** `handleServerStateChange()` method entirely.

**Leave `handleTransformation()` unchanged for now** — it still calls `pythonBridge.transformTextStreaming()`. Transforms continue to work via the Python server throughout Phase 1. The Python server Swift files are NOT deleted yet (that happens in Task 10). Phase 1 and Phase 2 must both be complete before merging to main — do not merge after Task 6.

Remove only the `pythonBridge.warmupTransformModel()` call from `TranscriptionCoordinator.handleTranscriptionSuccess` (already removed in Task 4). The rest of `handleTransformation()` stays untouched until Task 8.

**Remove** `deinit` call to `healthMonitor.stop()`:
```swift
deinit {
    hotkeyManager.stop()
}
```

**Update** `menuBarIcon` and `statusColor` — remove `startingServer` and `downloadingModels` cases, add `loadingModels`:
```swift
var menuBarIcon: String {
    switch status {
    case .loadingModels: return "arrow.down.circle"
    case .ready: return "waveform"
    case .recording: return "waveform.circle.fill"
    case .transcribing: return "text.bubble"
    case .error: return "exclamationmark.triangle"
    }
}

var statusColor: Color {
    switch status {
    case .loadingModels: return .blue
    case .ready: return .green
    case .recording: return .red
    case .transcribing: return .orange
    case .error: return .red
    }
}
```

**Remove** the `isServerOnline` check from `handleTranscriptionResult(.error)`:
```swift
// Remove this line:
if message.contains("not running") { isServerOnline = false }
```

- [ ] **Step 2: Update RayeeApp**

In `swift/Rayee/Rayee/RayeeApp.swift`, remove from `applicationDidFinishLaunching`:
```swift
// Remove:
ServerManager.shared.start()
```

Remove from `applicationWillTerminate`:
```swift
// Remove:
ServerManager.shared.stop()
```

- [ ] **Step 3: Build to verify it compiles**

```bash
cd swift/Rayee
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```
Fix any residual references to `isServerOnline`, `serverManager`, `healthMonitor`, or `pythonBridge` in AppState. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add swift/Rayee/Rayee/AppState.swift swift/Rayee/Rayee/RayeeApp.swift
git commit -m "feat: update AppState and RayeeApp for server-less WhisperKit startup"
```

---

### Task 6: Update Models settings UI

**Files:**
- Modify: `swift/Rayee/Rayee/ModelsSettingsTab.swift`

Replace all `FasterWhisperManager` references with `WhisperKitModelManager`. The UI shows the same information: model list, download button, delete button, size, active indicator.

- [ ] **Step 1: Read current ModelsSettingsTab**

```bash
cat swift/Rayee/Rayee/ModelsSettingsTab.swift
```

- [ ] **Step 2: Replace FasterWhisperManager references**

Find every occurrence of `FasterWhisperManager`, `FWModelInfo`, `FWModelStatus` in `ModelsSettingsTab.swift` and replace:

| Old | New |
|-----|-----|
| `@StateObject var modelManager = FasterWhisperManager.shared` | `@StateObject var modelManager = WhisperKitModelManager.shared` |
| `FWModelInfo` | `WKModelInfo` |
| `FWModelStatus.ready` | `WKModelStatus.ready` |
| `FWModelStatus.notDownloaded` | `WKModelStatus.notDownloaded` |
| `FWModelStatus.downloading` | `WKModelStatus.downloading(fractionCompleted: _)` |
| `FWModelStatus.error` | `WKModelStatus.error(_)` |
| `model.status == .downloading` | `if case .downloading = model.status { ... }` |
| `modelManager.downloadModel(model.id)` | `modelManager.downloadModel(model.id)` *(unchanged)* |
| `modelManager.deleteModel(model.id)` | `modelManager.deleteModel(model.id)` *(unchanged)* |
| `modelManager.selectedModelName == model.id` | `modelManager.selectedModelName == model.id` *(unchanged)* |
| `.onAppear { Task { await modelManager.refreshModels() } }` | `.onAppear { Task { await modelManager.refreshModels() } }` *(unchanged)* |

Also update the model selection action to call `modelManager.selectModel(model.id)` and then `AppState.shared.loadWhisperModel()` to reload WhisperKit with the new model.

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add swift/Rayee/Rayee/ModelsSettingsTab.swift
git commit -m "feat: update Models UI to use WhisperKitModelManager"
```

---

## Phase 2: MLX LLM Transforms

---

### Task 7: Create MLXTransformManager

**Files:**
- Create: `swift/Rayee/Rayee/MLXTransformManager.swift`
- Create: `swift/Rayee/RayeeTests/MLXTransformManagerTests.swift`

`MLXTransformManager` wraps mlx-swift-lm for streaming text transforms. It keeps the loaded model in memory and auto-unloads after 30s idle. Transform prompts are migrated from the Python `transform_prompts.py`.

> **Before coding:** Read `https://github.com/ml-explore/mlx-swift-lm/blob/main/README.md` in the repo to confirm the exact `generate()` call signature. The AsyncStream API was confirmed in research but method parameters may have changed. Use `gh api repos/ml-explore/mlx-swift-lm/contents/Libraries/MLXLLM/MLXLLM.swift` to read the public API surface.

- [ ] **Step 1: Write failing test**

Create `swift/Rayee/RayeeTests/MLXTransformManagerTests.swift`:

```swift
import XCTest
@testable import Rayee

final class MLXTransformManagerTests: XCTestCase {

    func testBuildPromptGrammar() {
        let (system, user) = MLXTransformManager.buildPrompt(text: "hello world", type: .grammar)
        XCTAssertTrue(system.contains("transformation assistant"))
        XCTAssertTrue(user.contains("hello world"))
        XCTAssertTrue(user.contains("grammar"))
    }

    func testBuildPromptBullets() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "item one item two", type: .bullets)
        XCTAssertTrue(user.contains("bullet"))
        XCTAssertTrue(user.contains("item one item two"))
    }

    func testBuildPromptFormal() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "hey what's up", type: .formal)
        XCTAssertTrue(user.contains("formal"))
    }

    func testBuildPromptCasual() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "Please be advised", type: .casual)
        XCTAssertTrue(user.contains("casual"))
    }

    func testBuildPromptRephrase() {
        let (_, user) = MLXTransformManager.buildPrompt(text: "The quick brown fox", type: .rephrase)
        XCTAssertTrue(user.contains("clearer"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd swift/Rayee
xcodebuild test -scheme RayeeTests -destination "platform=macOS" 2>&1 | grep -E "error:|FAIL"
```
Expected: compile error — `MLXTransformManager` doesn't exist.

- [ ] **Step 3: Create MLXTransformManager**

Create `swift/Rayee/Rayee/MLXTransformManager.swift`:

```swift
import Foundation
import MLXLLM
import MLXLMCommon

@MainActor
class MLXTransformManager: ObservableObject {
    static let shared = MLXTransformManager()

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isModelLoading = false
    @Published private(set) var isModelDownloaded = false
    @Published var loadError: String?

    private var modelContainer: ModelContainer?
    private var unloadTimer: Timer?
    private let unloadDelay: TimeInterval = 30

    private init() {}

    // MARK: - Model Lifecycle

    func loadModelIfNeeded() async {
        guard modelContainer == nil else {
            resetUnloadTimer()
            return
        }
        isModelLoading = true
        loadError = nil

        do {
            let config = ModelConfiguration(id: "mlx-community/Llama-3.2-1B-Instruct-4bit")
            modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: config)
            isModelLoaded = true
            isModelDownloaded = true
            AppLogger.log("MLX model loaded", category: "transform")
            resetUnloadTimer()
        } catch {
            loadError = error.localizedDescription
            AppLogger.log("MLX model load failed: \(error)", category: "transform")
        }

        isModelLoading = false
    }

    private func resetUnloadTimer() {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(withTimeInterval: unloadDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.unloadModel()
            }
        }
    }

    private func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        AppLogger.log("MLX model unloaded (idle timeout)", category: "transform")
    }

    // MARK: - Transform

    func streamTransform(
        text: String,
        type: TransformationType,
        onToken: @escaping (String) -> Void
    ) async throws {
        await loadModelIfNeeded()
        guard let container = modelContainer else {
            throw MLXTransformError.modelNotLoaded
        }

        resetUnloadTimer()

        let (systemPrompt, userPrompt) = Self.buildPrompt(text: text, type: type)

        // Build chat messages and generate
        // NOTE: Verify exact generate() signature against mlx-swift-lm source before finalizing.
        // The AsyncStream<Generation> API was confirmed in research but parameter names may vary.
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let generateInput = try await container.perform { context in
            try context.processor.prepare(input: .init(messages: messages))
        }

        let parameters = GenerateParameters(temperature: 0.0)

        for await generation in try MLXLMCommon.generate(
            input: generateInput,
            parameters: parameters,
            context: container
        ) {
            if case .chunk(let token) = generation {
                await MainActor.run { onToken(token) }
            }
        }
    }

    // MARK: - Prompts (migrated from Python transform_prompts.py)

    static func buildPrompt(text: String, type: TransformationType) -> (system: String, user: String) {
        let system = "You are a text transformation assistant. You ONLY output the transformed text, nothing else. No explanations, no preamble, no quotes around the output."

        let user: String
        switch type {
        case .grammar:
            user = "Fix the grammar, spelling, and punctuation in the following text. Keep the original meaning and tone. Do not add or remove content.\n\n\(text)"
        case .bullets:
            user = "Convert the following text into a clean bullet point list. Each bullet should be concise. Use - for bullets.\n\n\(text)"
        case .rephrase:
            user = "Rephrase the following text to be clearer and more concise. Keep the same meaning but improve readability.\n\n\(text)"
        case .formal:
            user = "Rewrite the following text in a formal, professional tone. Keep the same meaning.\n\n\(text)"
        case .casual:
            user = "Rewrite the following text in a casual, friendly tone. Keep the same meaning.\n\n\(text)"
        }

        return (system, user)
    }
}

enum MLXTransformError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        "Transform model is not loaded. Please wait."
    }
}
```

> **Important:** If the `generate()` call signature doesn't match, read `Sources/MLXLMCommon/Generate.swift` in the mlx-swift-lm repo to find the correct API. The `container.perform { context in ... }` pattern and `GenerateParameters` type were confirmed in research.

- [ ] **Step 4: Run tests**

```bash
cd swift/Rayee
xcodebuild test -scheme RayeeTests -destination "platform=macOS" -only-testing:RayeeTests/MLXTransformManagerTests 2>&1 | grep -E "PASS|FAIL|error:"
```
Expected: all 5 tests pass.

- [ ] **Step 5: Build**

```bash
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 6: Commit**

```bash
git add swift/Rayee/Rayee/MLXTransformManager.swift swift/Rayee/RayeeTests/MLXTransformManagerTests.swift
git commit -m "feat: add MLXTransformManager with streaming transforms and 30s auto-unload"
```

---

### Task 8: Wire MLX transforms into AppState

**Files:**
- Modify: `swift/Rayee/Rayee/AppState.swift`

Replace the placeholder `handleTransformation()` from Task 5 with the real `MLXTransformManager.streamTransform()` call.

- [ ] **Step 1: Update handleTransformation in AppState**

In `swift/Rayee/Rayee/AppState.swift`, replace the placeholder `handleTransformation()`:

```swift
private func handleTransformation(type: TransformationType) {
    let text = recordingPanelController.transcribedText
    guard !text.isEmpty else { return }

    let transformState = recordingPanelController.transformState
    transformState.startTransformation(text: text, type: type)
    recordingPanelController.updateWindowSizeForTransform()

    Task { @MainActor in
        do {
            try await MLXTransformManager.shared.streamTransform(
                text: text,
                type: type,
                onToken: { [weak self] token in
                    transformState.appendStreamingToken(token)
                    self?.recordingPanelController.updateWindowSizeForTransform()
                }
            )
            transformState.completeTransformation(transformedText: transformState.streamingText)
            recordingPanelController.updateWindowSizeForTransform()
        } catch {
            transformState.failTransformation(message: error.localizedDescription)
            recordingPanelController.updateWindowSizeForTransform()
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add swift/Rayee/Rayee/AppState.swift
git commit -m "feat: wire MLXTransformManager into AppState transform handling"
```

---

### Task 9: Update Transforms settings UI

**Files:**
- Modify: `swift/Rayee/Rayee/TransformationsSettingsTab.swift`

Replace Python server status calls (`getTransformStatus`, `downloadTransformModel`) with `MLXTransformManager` state properties.

- [ ] **Step 1: Read current TransformationsSettingsTab**

```bash
cat swift/Rayee/Rayee/TransformationsSettingsTab.swift
```

- [ ] **Step 2: Replace server calls with MLXTransformManager state**

Remove any `Task { await pythonBridge.getTransformStatus() }` or similar calls.

Replace status display with `MLXTransformManager.shared` `@Published` properties:
```swift
@StateObject var transformManager = MLXTransformManager.shared

// Status text:
if transformManager.isModelLoading {
    Text("Loading model...")
} else if transformManager.isModelLoaded {
    Text("Model loaded (auto-unloads after 30s idle)")
} else if let error = transformManager.loadError {
    Text("Error: \(error)").foregroundColor(.red)
} else {
    Text("Model will load on first use")
}
```

Remove "Download model" button (mlx-swift-lm downloads automatically on first use).

Remove `keepTransformModelLoaded` toggle if present — the new architecture always auto-unloads.

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add swift/Rayee/Rayee/TransformationsSettingsTab.swift
git commit -m "feat: update Transforms UI to use MLXTransformManager state"
```

---

## Phase 3: Delete Python

---

### Task 10: Delete Python Swift infrastructure files

**Files:**
- Delete: `swift/Rayee/Rayee/PythonBridge.swift`
- Delete: `swift/Rayee/Rayee/UnixSocketProtocol.swift`
- Delete: `swift/Rayee/Rayee/ServerManager.swift`
- Delete: `swift/Rayee/Rayee/HealthMonitor.swift`
- Delete: `swift/Rayee/Rayee/FasterWhisperManager.swift`

After deletion, fix all remaining build errors from lingering references.

- [ ] **Step 1: Search for remaining references to deleted types**

```bash
cd swift/Rayee
grep -rn "PythonBridge\|UnixSocketProtocol\|ServerManager\|HealthMonitor\|FasterWhisperManager\|PythonBridgeError" Rayee/ --include="*.swift"
```

Note every file and line number that has references.

- [ ] **Step 2: Fix remaining references before deleting**

Common locations to check:
- `UploadManager.swift` — calls `pythonBridge.transcribeUpload()`. Replace with `WhisperKitManager.shared.transcribe()` after loading the audio file as `[Float]` via `AudioFileConverter`.
- `SetupGuideView.swift` — may reference `HealthMonitor.shared.isServerOnline`. Replace with `WhisperKitManager.shared.isLoaded`.
- Any `@EnvironmentObject` or `@ObservedObject` referencing `FasterWhisperManager`.

**First**, add `loadAudioAsFloat32(url:)` to `AudioFileConverter.swift` (it does NOT currently have this method — only `convertToWav`). Add the following static method to the `AudioFileConverter` class/struct:

```swift
import AVFoundation

static func loadAudioAsFloat32(url: URL) throws -> [Float] {
    // Re-read audio file as 16kHz mono Float32 — matches WhisperKit's expected format
    let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    let sourceFile = try AVAudioFile(forReading: url)
    let frameCount = AVAudioFrameCount(Double(sourceFile.length) * 16000 / sourceFile.fileFormat.sampleRate)

    guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
        throw AudioConverterError.conversionFailed
    }

    let converter = AVAudioConverter(from: sourceFile.processingFormat, to: outputFormat)!
    var error: NSError?
    converter.convert(to: buffer, error: &error) { _, outStatus in
        outStatus.pointee = .haveData
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat,
                                           frameCapacity: AVAudioFrameCount(sourceFile.length))!
        try? sourceFile.read(into: inputBuffer)
        return inputBuffer
    }

    if let error { throw error }
    guard let channelData = buffer.floatChannelData else {
        throw AudioConverterError.conversionFailed
    }
    return Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))
}
```

Also add the error type if it doesn't exist:
```swift
enum AudioConverterError: Error {
    case conversionFailed
}
```

**Then**, in `UploadManager.swift`, replace the transcription call:
```swift
// Old:
let text = try await pythonBridge.transcribeFile(audioPath: audioPath)

// New — convert file to [Float] then transcribe natively:
let audioData = try AudioFileConverter.loadAudioAsFloat32(url: audioURL)
let text = try await WhisperKitManager.shared.transcribe(
    audioBuffer: audioData,
    vocabulary: SettingsManager.shared.vocabularyList
)
```

- [ ] **Step 3: Build with all references fixed (before deleting files)**

```bash
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```
The build will still succeed because the files exist. Resolve all errors first.

- [ ] **Step 4: Delete the files from Xcode and disk**

In Xcode: right-click each file → Delete → Move to Trash.

Or from terminal (then remove from Xcode project via Xcode, or edit project.pbxproj):
```bash
rm swift/Rayee/Rayee/PythonBridge.swift
rm swift/Rayee/Rayee/UnixSocketProtocol.swift
rm swift/Rayee/Rayee/ServerManager.swift
rm swift/Rayee/Rayee/HealthMonitor.swift
rm swift/Rayee/Rayee/FasterWhisperManager.swift
```

After deleting, remove file references from Xcode project (Xcode will show them as missing — delete the red references).

- [ ] **Step 5: Build to verify clean compile**

```bash
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | grep -E "error:|BUILD"
```
Expected: `** BUILD SUCCEEDED **` with no errors.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: delete Python bridge, server manager, and health monitor — pure Swift"
```

---

### Task 11: Remove Python from app bundle and update docs

**Files:**
- Modify: `swift/Rayee/Rayee.xcodeproj` (build phases)
- Modify: `ROADMAP.md`
- Delete: `python/` directory

The Python server is embedded in the app bundle via a "Copy Files" build phase. Remove it. Also delete the Python source directory from the repo and update the ROADMAP.

- [ ] **Step 1: Remove Python from build phase**

In Xcode: Select the Rayee target → Build Phases → look for a "Copy Files" phase that copies the Python server or venv. Remove it.

Also check: Build Settings → "Bundle Resources" for any Python-related items.

- [ ] **Step 2: Verify app bundle size decreases**

Build (not archive — archive requires code signing certs that may not be in CI) and check:

```bash
cd swift/Rayee
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | tail -5

# Find the built .app and check its size
find ~/Library/Developer/Xcode/DerivedData -name "Rayee.app" -maxdepth 8 2>/dev/null | head -1 | xargs du -sh
```
The Python venv alone is ~500MB — the app should be dramatically smaller without it.

- [ ] **Step 3: Update publish_release.sh to remove Python bundling**

`publish_release.sh` currently: checks for Python 3, runs PyInstaller to build `python/dist/RayeeServer`, and copies it into the app bundle. All of this must be removed.

Open `publish_release.sh` and delete:
1. Any block that checks for Python (`command -v python3`, `pip install`, `pyinstaller`, etc.)
2. The `cp -r python/dist/RayeeServer` line that copies the server into the bundle
3. Any reference to `RayeeServer` in bundle resource copying

The release script should now be a straight: bump version → build → sign DMG → upload. Verify it still contains the EdDSA signing step (`sign_update`) and Sparkle appcast update — those are not being removed.

After editing, confirm no Python references remain:
```bash
grep -n "python\|pyinstaller\|RayeeServer\|venv" publish_release.sh
```
Expected: no output.

- [ ] **Step 4: Delete the Python directory from the repo**

```bash
rm -rf python/
```

- [ ] **Step 5: Update ROADMAP.md**

Replace the "Blocked: Eliminate Python" section with:

```markdown
## Completed: Eliminated Python — Pure Native App

**Shipped in v0.4.** Replaced the Python server with:
- WhisperKit (argmax-oss-swift v1.0.0) for CoreML transcription
- mlx-swift-lm v3.31.3 for Metal-accelerated LLM transforms

Single .app binary, no Python dependency, instant startup.
```

- [ ] **Step 6: Remove Python setup from SetupGuideView**

In `swift/Rayee/Rayee/SetupGuideView.swift`, remove any checklist items or status indicators that reference the Python server, pip install, or virtual environment.

- [ ] **Step 7: Final build and run tests**

```bash
cd swift/Rayee
xcodebuild test -scheme RayeeTests -destination "platform=macOS" 2>&1 | grep -E "PASS|FAIL|error:"
xcodebuild build -scheme Rayee -destination "platform=macOS" 2>&1 | tail -5
```
Expected: all tests pass, build succeeds.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: remove Python server from app bundle and repository — v0.4 pure Swift"
```

---

## Self-Review Checklist

After writing this plan, reviewing against spec (ROADMAP.md):

**Spec coverage:**
- ✅ Replace Python transcription with WhisperKit → Tasks 2, 3, 4, 5
- ✅ Replace Python transforms with mlx-swift-lm → Tasks 7, 8, 9
- ✅ Delete all Python infrastructure → Tasks 10, 11
- ✅ Model management UI updated → Tasks 3, 6
- ✅ Vocabulary (custom prompt) migrated → Task 2 (promptTokens)
- ✅ Raw PCM input path preserved → Task 4 (audioBuffer: [Float])
- ✅ Streaming transforms preserved → Task 7 (AsyncStream)
- ✅ Auto-unload after idle → Task 7 (30s Timer)

**Gaps identified and addressed:**
- ✅ UploadManager transcription path → Task 10 (with `AudioFileConverter.loadAudioAsFloat32`)
- ✅ SetupGuideView server status removal → Task 11
- ✅ Package rename (WhisperKit → argmax-oss-swift URL) → Task 1
- ✅ Model name format change (FW names vs CoreML names) → Task 3 (displayName transform)
- ✅ **UserDefaults migration**: Old `selectedModel` ("small" → "openai_whisper-small") migrated on first access → Task 4
- ✅ **publish_release.sh Python bundling**: Removed in Task 11 Step 3
- ✅ **Task 1 human-driven**: Marked with explicit banner; subagents start at Task 2
- ✅ **macOS deployment target**: Task 1 Step 5 checks and bumps to 14.0 if needed
- ✅ **Transforms not broken during Phase 1**: PythonBridge for transforms preserved until Task 8; phases 1+2 merged together
- ✅ **API signature verification**: Task 2 Step 3 verifies WhisperKit signatures before coding; Task 7 has pre-coding verify note
- ⚠️ **Users with downloaded Faster-Whisper models**: Those files remain in `~/.rayee/models/` (not touched). WhisperKit downloads to a different location. Old files simply orphaned — acceptable.
