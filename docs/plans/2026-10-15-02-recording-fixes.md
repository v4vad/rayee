# Phase 2: Recording and Feedback Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make recording dependable and honest. Show errors, stop at a natural pause, never clip the first word or repeat audio, give the user's clipboard back, open the setup guide on first launch, and keep Smart Dictation's history and Discard behaviour correct.

**Architecture:** Fixable logic is pulled into small pure helpers so it can be unit-tested without a microphone or AI model: `UserFacingError`, `SpeechGate`, `AudioRecorder.convert`, `ClipboardSnapshot`, `SmartDictationPolicy` and `SettingsManager.clampedSilenceDuration`. The UI and app-flow changes around them are checked by hand.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation (`AVAudioEngine`, `AVAudioConverter`), AppKit (`NSPasteboard`), XCTest.

**Spec:** `docs/plans/2026-10-15-00-improvement-roadmap.md`, findings F1–F4, F7–F10 and F12–F14. **Phase 1 (`2026-10-15-01-cleanup.md`) must be done first.** The code snippets below assume its deletions, for example `RecordingResult` no longer has `audioPath`, and `AudioRecorderError` has exactly three cases.

## Global Constraints

See the roadmap file. New app code goes into **existing** files, so no `project.pbxproj` edits are needed. New test files go in `swift/Rayee/RayeeTests/`, which syncs automatically.

## Review Focus

These lines come from the roadmap's Review focus list. Each is pinned to a task here:
- Microphone permission denied → Task 1, `testMicrophonePermissionMessageExplainsWhereToFixIt`, plus a manual check.
- Clipboard held an image → Task 5, `testRestoresNonTextData`.
- Speaking the instant the hotkey is pressed, with adaptive mode on → Task 4, `testSpeakingImmediatelyKeepsTheFirstWord`.
- Discard pressed while Smart Dictation is writing → Task 7, manual check (the AI model can't run in unit tests).
- A dictated question being answered rather than cleaned is Phase 3's job. It's out of scope here.

---

### Task 1: Show errors in the panel, including a denied microphone (F1, F2)

**Files:**
- Modify: `swift/Rayee/Rayee/TranscriptionCoordinator.swift` (add `UserFacingError`, use it for errors, detect denied mic)
- Modify: `swift/Rayee/Rayee/RecordingPanelController.swift` (error state)
- Modify: `swift/Rayee/Rayee/RecordingPanelView.swift` (error content and footer)
- Modify: `swift/Rayee/Rayee/AppState.swift` (show the error instead of hiding the panel)
- Modify: `swift/Rayee/Rayee/Config.swift` (panel height)
- Test: `swift/Rayee/RayeeTests/UserFacingErrorTests.swift` (new)

**Interfaces:**
- Consumes: `AudioRecorderError` with exactly `.noMicrophonePermission`, `.engineStartFailed(String)` and `.noAudioRecorded`; `WhisperKitError.modelNotLoaded`; `AudioRecorder.hasMicrophonePermission() -> Bool`.
- Produces: `enum UserFacingError { static func message(for error: Error) -> String }`; `RecordingPanelController.errorMessage: String?`; `RecordingPanelController.showErrorMode(message: String)`; `Config.recordingPanelHeightError`.

- [ ] **Step 1: Write the failing test**

Create `swift/Rayee/RayeeTests/UserFacingErrorTests.swift`:

```swift
import XCTest
@testable import Rayee

final class UserFacingErrorTests: XCTestCase {

    func testMicrophonePermissionMessageExplainsWhereToFixIt() {
        let message = UserFacingError.message(for: AudioRecorderError.noMicrophonePermission)
        XCTAssertTrue(message.contains("System Settings"))
        XCTAssertTrue(message.contains("Microphone"))
    }

    func testMicrophoneStartFailureMessage() {
        let message = UserFacingError.message(for: AudioRecorderError.engineStartFailed("-10868"))
        XCTAssertTrue(message.contains("microphone"))
    }

    func testModelStillLoadingMessage() {
        let message = UserFacingError.message(for: WhisperKitError.modelNotLoaded)
        XCTAssertTrue(message.contains("still loading"))
    }

    func testUnknownErrorFallsBackToItsDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Boom"])
        XCTAssertEqual(UserFacingError.message(for: error), "Transcription failed: Boom")
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run the test command with `-only-testing:RayeeTests/UserFacingErrorTests`.
Expected: the build fails with `cannot find 'UserFacingError' in scope`.

- [ ] **Step 3: Add `UserFacingError` and use it in the coordinator**

In `TranscriptionCoordinator.swift`, add this right after the `TranscriptionResult` enum:

```swift
/// Turns internal errors into short, plain-language messages for the recording panel.
enum UserFacingError {
    static func message(for error: Error) -> String {
        if let recorderError = error as? AudioRecorderError {
            switch recorderError {
            case .noMicrophonePermission:
                return "Rayee can't use the microphone. Allow it in System Settings → Privacy & Security → Microphone, then try again."
            case .engineStartFailed:
                return "Couldn't start the microphone. Check that one is connected and not in use by another app."
            case .noAudioRecorded:
                return "Rayee didn't hear anything. Check your microphone and try again."
            }
        }
        if let whisperError = error as? WhisperKitError, case .modelNotLoaded = whisperError {
            return "The speech model is still loading. Try again in a few seconds."
        }
        return "Transcription failed: \(error.localizedDescription)"
    }
}
```

Then make these replacements in the same file:

a) In `handleRecordingComplete`, replace:
```swift
            if case .noAudioRecorded = error {
                AppLogger.log("Recording ended with no speech detected", category: "transcription")
```
with:
```swift
            if case .noAudioRecorded = error {
                // A denied microphone records pure silence. Say so instead of silently closing.
                if !AudioRecorder.hasMicrophonePermission() {
                    AppLogger.log("No speech heard and microphone permission is missing", category: "transcription")
                    handleRecordingError(AudioRecorderError.noMicrophonePermission)
                    return
                }
                AppLogger.log("Recording ended with no speech detected", category: "transcription")
```

b) In `handleRecordingError`, replace
`        onTranscriptionComplete?(.error(message: error.localizedDescription))`
with
`        onTranscriptionComplete?(.error(message: UserFacingError.message(for: error)))`

c) In `handleTranscriptionError`, make the same replacement:
`        onTranscriptionComplete?(.error(message: error.localizedDescription))`
becomes
`        onTranscriptionComplete?(.error(message: UserFacingError.message(for: error)))`

- [ ] **Step 4: Run the test to confirm it passes**

Run the same command. Expected: `TEST SUCCEEDED`, 4 tests.

- [ ] **Step 5: Add the error state to the panel controller**

In `Config.swift`, after `recordingPanelHeightWithTransform`, add:
```swift

    /// Height — Error state (message + Dismiss)
    static let recordingPanelHeightError: CGFloat = 170
```

In `RecordingPanelController.swift`:

a) After `@Published var recordingDuration: TimeInterval = 0`, add:
```swift

    /// Error message shown in the panel (nil = no error)
    @Published var errorMessage: String?
```

b) In `hidePanel()`, after `transcribedText = ""`, add `        errorMessage = nil`.

c) In `setRecording(_:)`, inside `if recording {`, after `audioLevelMonitor.reset()`, add `            errorMessage = nil`.

d) After `showResultMode(text:)`, add:
```swift

    /// Show an error message in the panel until the user dismisses it
    func showErrorMode(message: String) {
        errorMessage = message
        showResult = false
        isRecording = false
        isTranscribing = false
        showPanel()
    }
```

e) In `updateWindowSize()`, replace
`        if transformState.showPreview || transformState.isTransforming {`
with
```swift
        if errorMessage != nil {
            newHeight = Config.recordingPanelHeightError
        } else if transformState.showPreview || transformState.isTransforming {
```

f) In `RecordingPanelHostView.body`, replace
`            onUseOriginal: { controller.onUseOriginal?() }`
with
```swift
            onUseOriginal: { controller.onUseOriginal?() },
            errorMessage: controller.errorMessage
```

- [ ] **Step 6: Draw the error state in the panel view**

In `RecordingPanelView.swift`:

a) After `    var onUseOriginal: (() -> Void)?`, add:
```swift
    var errorMessage: String? = nil
```

b) In `contentView`, replace
`        if let tState = transformState, tState.isActive {`
with
```swift
        if let message = errorMessage {
            errorContent(message)
        } else if let tState = transformState, tState.isActive {
```

c) In `footerView`, replace
```swift
        if showResult {
            resultActions
                .frame(height: 46)
```
with
```swift
        if errorMessage != nil {
            errorFooter
                .frame(height: 46)
        } else if showResult {
            resultActions
                .frame(height: 46)
```

d) Add this section just before `    // MARK: - Timer helper`:
```swift
    // MARK: - Error state

    private func errorContent(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(accentRed)
            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var errorFooter: some View {
        HStack {
            Text("Something went wrong")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(accentRed)
                .padding(.leading, 20)

            Spacer()

            Button("Dismiss", action: onDiscard)
                .buttonStyle(GrayPillButtonStyle())
                .padding(.trailing, 20)
        }
    }

```

- [ ] **Step 7: Show the error instead of hiding the panel**

In `AppState.swift`, `handleTranscriptionResult`, replace:
```swift
        case .error(let message):
            errorMessage = message
            status = .error
            // Hide the panel on error
            recordingPanelController.hidePanel()
```
with:
```swift
        case .error(let message):
            errorMessage = message
            status = .error
            // Keep the panel open and explain what went wrong; Dismiss closes it
            recordingPanelController.showErrorMode(message: message)
```

(`onDiscard` already calls `hidePanel()`, which clears `errorMessage`.)

- [ ] **Step 8: Build, run all tests, and check by hand**

Run the build and test commands. Expected: both succeed.
Manual check (ask the user to do this with you):
1. Quit Rayee. Then reset its microphone permission: `tccutil reset Microphone com.rayee.app`
2. Run from Xcode (Cmd+R). Press the hotkey, click **Don't Allow** on the prompt, say something, then press the hotkey again.
   Expected: the panel stays open with the red "can't use the microphone" message, and **Dismiss** closes it.
3. Re-allow the microphone in System Settings → Privacy & Security → Microphone, and confirm normal dictation works.

- [ ] **Step 9: Commit**

```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: show transcription and microphone errors in the panel"
```

---

### Task 2: Stop at a natural pause and allow longer recordings (F3, F4)

**Files:**
- Modify: `swift/Rayee/Rayee/Config.swift` (four values)
- Modify: `swift/Rayee/Rayee/SettingsManager.swift` (one-time migration and clamp)
- Modify: `swift/Rayee/Rayee/GeneralSettingsTab.swift` (slider and wording)
- Test: `swift/Rayee/RayeeTests/RecordingLimitsTests.swift` (new)

**Interfaces:**
- Produces: `static func SettingsManager.clampedSilenceDuration(_ seconds: Double) -> Double`; `SettingsKey.silenceDurationMigratedV08`.

- [ ] **Step 0: CONFIRM WITH USER**

Ask the user, in plain words:
> "Right now Rayee waits 30 seconds of silence before it stops by itself, so in practice you press the hotkey to stop. I'd change it to stop after **2 seconds** of quiet (adjustable from 1 to 10 seconds), and reset everyone's setting to 2 seconds once, because the old slider couldn't go below 5. I'd also raise the recording limit from 1 minute to 5 minutes. OK?"

If they want different numbers, use theirs in Steps 1 and 3 and in the test. Record the decision in the roadmap's Decisions log.

- [ ] **Step 1: Write the failing test**

Create `swift/Rayee/RayeeTests/RecordingLimitsTests.swift`:

```swift
import XCTest
@testable import Rayee

final class RecordingLimitsTests: XCTestCase {

    func testStopsAfterTwoSecondsOfSilenceByDefault() {
        XCTAssertEqual(Config.defaultSilenceDuration, 2.0)
    }

    func testRecordingLimitIsFiveMinutes() {
        XCTAssertEqual(Config.maxRecordingDuration, 300)
    }

    func testOldThirtySecondSettingIsClampedIntoNewRange() {
        XCTAssertEqual(SettingsManager.clampedSilenceDuration(30), 10)
    }

    func testTooShortIsRaisedToMinimum() {
        XCTAssertEqual(SettingsManager.clampedSilenceDuration(0.2), 1)
    }

    func testValueInRangeIsKept() {
        XCTAssertEqual(SettingsManager.clampedSilenceDuration(2.5), 2.5)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run the test command with `-only-testing:RayeeTests/RecordingLimitsTests`.
Expected: the build fails with `type 'SettingsManager' has no member 'clampedSilenceDuration'`.

- [ ] **Step 3: Change the values in `Config.swift`**

Replace:
```swift
    /// Maximum recording duration before auto-stop (seconds)
    static let maxRecordingDuration: TimeInterval = 60.0

    /// Default timeout before stopping (seconds) - user can override in settings
    static let defaultSilenceDuration: TimeInterval = 30.0

    /// Minimum silence duration for the settings slider (seconds)
    static let minSilenceDuration: TimeInterval = 5.0

    /// Maximum silence duration for the settings slider (seconds)
    static let maxSilenceDuration: TimeInterval = 60.0
```
with:
```swift
    /// Maximum recording duration before auto-stop (seconds), when the timeout switch is on
    static let maxRecordingDuration: TimeInterval = 300.0

    /// Default pause length that ends a recording (seconds) - user can override in settings
    static let defaultSilenceDuration: TimeInterval = 2.0

    /// Minimum silence duration for the settings slider (seconds)
    static let minSilenceDuration: TimeInterval = 1.0

    /// Maximum silence duration for the settings slider (seconds)
    static let maxSilenceDuration: TimeInterval = 10.0
```

- [ ] **Step 4: Add the clamp and the one-time reset in `SettingsManager.swift`**

a) In `enum SettingsKey`, after `static let smartDictationEnabled = "smartDictationEnabled"`, add:
```swift
    static let silenceDurationMigratedV08 = "silenceDurationMigratedV08"
```

b) Replace:
```swift
        // Load silence duration setting (default: 30 seconds)
        if let savedDuration = UserDefaults.standard.object(forKey: SettingsKey.silenceDuration) as? Double {
            self.silenceDuration = savedDuration
        } else {
            self.silenceDuration = 30.0
        }
```
with:
```swift
        // Load silence duration setting (default: Config.defaultSilenceDuration).
        // v0.8: the old slider ran 5–60s with a 30s default, so any saved value is on the
        // old scale. Clear it once so everyone starts on the new default.
        if !UserDefaults.standard.bool(forKey: SettingsKey.silenceDurationMigratedV08) {
            UserDefaults.standard.removeObject(forKey: SettingsKey.silenceDuration)
            UserDefaults.standard.set(true, forKey: SettingsKey.silenceDurationMigratedV08)
        }
        if let savedDuration = UserDefaults.standard.object(forKey: SettingsKey.silenceDuration) as? Double {
            self.silenceDuration = Self.clampedSilenceDuration(savedDuration)
        } else {
            self.silenceDuration = Config.defaultSilenceDuration
        }
```

c) In `resetToDefaults()`, replace `        silenceDuration = 30.0` with `        silenceDuration = Config.defaultSilenceDuration`.

d) Replace the comment above `timeoutEnabled`:
```swift
    // Whether to enforce a 60-second maximum recording time
```
with
```swift
    // Whether to enforce the Config.maxRecordingDuration (5-minute) recording limit
```

e) Just before `    // Save hotkey configuration to UserDefaults`, add:
```swift
    /// Keeps a saved silence duration inside the slider's range.
    static func clampedSilenceDuration(_ seconds: Double) -> Double {
        min(max(seconds, Config.minSilenceDuration), Config.maxSilenceDuration)
    }

```

- [ ] **Step 5: Run the test to confirm it passes**

Run the same command. Expected: `TEST SUCCEEDED`, 5 tests.

- [ ] **Step 6: Update the General tab**

In `GeneralSettingsTab.swift`:

a) Replace `                Text("When enabled, recording stops after 60 seconds")` with `                Text("When enabled, recording stops after 5 minutes")`.

b) Replace `                    Text(String(format: "%.0fs", settings.silenceDuration))` with `                    Text(String(format: "%.1fs", settings.silenceDuration))`.

c) Replace
```swift
                    in: Config.minSilenceDuration...Config.maxSilenceDuration,
                    step: 5
```
with
```swift
                    in: Config.minSilenceDuration...Config.maxSilenceDuration,
                    step: 0.5
```

d) Replace `                Text("After you stop speaking, recording ends after this many seconds of silence")` with `                Text("Recording ends after you've been quiet this long. You can always press the hotkey to stop sooner.")`.

- [ ] **Step 7: Build, run all tests, and check by hand**

Run the build and test commands. Expected: both succeed.
Manual check: run the app, press the hotkey, say one sentence, then stay quiet.
Expected: the recording stops about 2 seconds after you finish, and the text appears. Settings → General shows "2.0s".

- [ ] **Step 8: Commit**

```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: stop after a 2s pause by default and allow 5-minute recordings"
```

---

### Task 3: Never feed the same audio to the converter twice (F10)

**Files:**
- Modify: `swift/Rayee/Rayee/AudioRecorder.swift` (new `static func convert`, used by `processAudioBuffer`)
- Test: `swift/Rayee/RayeeTests/AudioConversionTests.swift` (new)

**Interfaces:**
- Produces: `static func AudioRecorder.convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer?`. Task 4 calls it.

- [ ] **Step 1: Write the failing test**

Create `swift/Rayee/RayeeTests/AudioConversionTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import Rayee

final class AudioConversionTests: XCTestCase {

    private let micFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    private let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// A slowly rising ramp, split into 100ms microphone-sized buffers.
    private func rampBuffers(count: Int, framesPerBuffer: Int = 4_800) -> [AVAudioPCMBuffer] {
        (0..<count).map { bufferIndex in
            let buffer = AVAudioPCMBuffer(
                pcmFormat: micFormat, frameCapacity: AVAudioFrameCount(framesPerBuffer))!
            buffer.frameLength = AVAudioFrameCount(framesPerBuffer)
            let data = buffer.floatChannelData![0]
            for i in 0..<framesPerBuffer {
                data[i] = Float(bufferIndex * framesPerBuffer + i) / 240_000
            }
            return buffer
        }
    }

    private func convertAll(_ buffers: [AVAudioPCMBuffer]) -> [Float] {
        let converter = AVAudioConverter(from: micFormat, to: whisperFormat)!
        var samples: [Float] = []
        for buffer in buffers {
            guard let converted = AudioRecorder.convert(buffer, using: converter, to: whisperFormat) else {
                continue
            }
            samples.append(contentsOf: UnsafeBufferPointer(
                start: converted.floatChannelData![0], count: Int(converted.frameLength)))
        }
        return samples
    }

    func testOutputIsOneThirdOfInputLength() {
        let samples = convertAll(rampBuffers(count: 5))  // 24,000 frames at 48kHz
        XCTAssertEqual(Double(samples.count), 8_000, accuracy: 100)
    }

    func testAudioIsNeverRepeated() {
        // A rising ramp must keep rising. If the converter re-reads a buffer, it jumps back down.
        let samples = convertAll(rampBuffers(count: 5))
        let warmUp = 64  // skip the resampler's start-up ripple
        guard samples.count > warmUp + 1 else { return XCTFail("no output") }
        for i in (warmUp + 1)..<samples.count where samples[i] < samples[i - 1] - 0.005 {
            return XCTFail("audio jumped backwards at sample \(i): \(samples[i - 1]) → \(samples[i])")
        }
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run the test command with `-only-testing:RayeeTests/AudioConversionTests`.
Expected: the build fails with `type 'AudioRecorder' has no member 'convert'`.

- [ ] **Step 3: Add `convert` and use it**

In `AudioRecorder.swift`, add this just above `    /// Process incoming audio buffer`:

```swift
    /// Converts one microphone buffer to 16kHz mono.
    /// The input block hands the buffer over exactly once, then reports "no data for now".
    /// Returning the same buffer on every call makes the converter read the same audio twice
    /// whenever it asks for more input to fill its output.
    static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            print("[AudioRecorder] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }
        return output
    }

```

Then in `processAudioBuffer`, replace:
```swift
        // Convert to our target format (16kHz mono)
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * (sampleRate / buffer.format.sampleRate)
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else {
            print("[AudioRecorder] Conversion error: \(error?.localizedDescription ?? "unknown")")
            return
        }
```
with:
```swift
        // Convert to our target format (16kHz mono)
        guard let convertedBuffer = AudioRecorder.convert(buffer, using: converter, to: targetFormat) else {
            return
        }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run the same command. Expected: `TEST SUCCEEDED`, 2 tests.

- [ ] **Step 5: Confirm the test would have caught the old bug (record the result)**

Temporarily change the input block in `convert` back to the old behaviour (`inputStatus.pointee = .haveData; return buffer` every time), then run the test again.
- If `testAudioIsNeverRepeated` (or the length test) fails, the bug was real on this Mac. Write "F10 confirmed" in the Session log.
- If both still pass, the repeat doesn't happen in this setup. Write "F10 not reproduced; fix kept as the documented-safe pattern" in the Session log.

Either way, **restore the fixed version** and re-run so it passes.

- [ ] **Step 6: Build, run all tests, commit**

Run the build and test commands. Expected: both succeed.
```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: hand each mic buffer to the converter once so audio is never repeated"
```

---

### Task 4: Keep the first word: pre-roll and safer adaptive calibration (F8, F9)

**Files:**
- Modify: `swift/Rayee/Rayee/AudioRecorder.swift` (add `SpeechGate`, use it)
- Modify: `swift/Rayee/Rayee/Config.swift` (two constants)
- Test: `swift/Rayee/RayeeTests/SpeechGateTests.swift` (new)

**Interfaces:**
- Consumes: `AudioRecorder.convert(_:using:to:)` from Task 3.
- Produces: `struct SpeechGate` with `init(fixedThreshold: Float = Config.silenceThreshold, adaptive: Bool, preRollSampleLimit: Int = …)`, `mutating func feed(_ samples: [Float], rms: Float) -> Bool`, `var speechDetected: Bool { get }`, `var kept: [Float] { get }`, `var threshold: Float { get }` and `static func adaptedThreshold(from rmsValues: [Float]) -> Float`; `Config.preRollDuration`; `Config.maxAdaptiveSilenceThreshold`.

- [ ] **Step 1: Write the failing test**

Create `swift/Rayee/RayeeTests/SpeechGateTests.swift`:

```swift
import XCTest
@testable import Rayee

final class SpeechGateTests: XCTestCase {

    func testKeepsShortPreRollBeforeSpeech() {
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: false, preRollSampleLimit: 3)
        XCTAssertFalse(gate.feed([0.1, 0.2], rms: 0.001))
        XCTAssertFalse(gate.feed([0.3, 0.4], rms: 0.001))
        XCTAssertTrue(gate.feed([0.9], rms: 0.5))
        XCTAssertEqual(gate.kept, [0.2, 0.3, 0.4, 0.9])
    }

    func testKeepsNothingWhenNoSpeech() {
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: false, preRollSampleLimit: 3)
        _ = gate.feed([0.1, 0.2, 0.3, 0.4], rms: 0.001)
        XCTAssertFalse(gate.speechDetected)
        XCTAssertTrue(gate.kept.isEmpty)
    }

    func testKeepsQuietGapsOnceSpeechHasStarted() {
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: false, preRollSampleLimit: 0)
        XCTAssertTrue(gate.feed([0.9], rms: 0.5))
        XCTAssertFalse(gate.feed([0.0], rms: 0.001))
        XCTAssertEqual(gate.kept, [0.9, 0.0])
    }

    func testQuietRoomUsesTheMinimumThreshold() {
        XCTAssertEqual(SpeechGate.adaptedThreshold(from: [0.001, 0.001]), Config.minSilenceThreshold)
    }

    func testThresholdIsCappedWhenUserTalksDuringCalibration() {
        XCTAssertEqual(SpeechGate.adaptedThreshold(from: [0.2, 0.25]), Config.maxAdaptiveSilenceThreshold)
    }

    func testSpeakingImmediatelyKeepsTheFirstWord() {
        // Review focus: the user talks the instant the hotkey is pressed, with adaptive mode on.
        var gate = SpeechGate(fixedThreshold: 0.01, adaptive: true, preRollSampleLimit: 4_800)
        XCTAssertFalse(gate.feed([0.5, 0.5], rms: 0.2))  // calibration chunk 1 (already speech)
        XCTAssertFalse(gate.feed([0.6, 0.6], rms: 0.2))  // calibration chunk 2
        XCTAssertTrue(gate.feed([0.7], rms: 0.2))        // still recognised as speech
        XCTAssertEqual(gate.kept, [0.5, 0.5, 0.6, 0.6, 0.7])
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run the test command with `-only-testing:RayeeTests/SpeechGateTests`.
Expected: the build fails with `cannot find 'SpeechGate' in scope`.

- [ ] **Step 3: Add the constants and `SpeechGate`**

In `Config.swift`, after `minSilenceThreshold`, add:
```swift

    /// Highest threshold adaptive VAD may choose. Stops speech during calibration from
    /// pushing the threshold above normal speaking level.
    static let maxAdaptiveSilenceThreshold: Float = 0.03

    /// Audio kept from just before speech is detected, so soft first sounds aren't clipped (seconds)
    static let preRollDuration: TimeInterval = 0.3
```

At the end of `AudioRecorder.swift`, after the class's closing `}`, add:

```swift

/// Decides which samples to keep and whether each chunk is speech.
/// Pure logic with no audio hardware, so it can be unit-tested with made-up chunks.
struct SpeechGate {
    private let adaptive: Bool
    private let preRollSampleLimit: Int
    private let calibrationChunkTarget = 2  // 2 chunks × 100ms = 200ms

    private(set) var threshold: Float
    private(set) var speechDetected = false
    private(set) var kept: [Float] = []

    private var preRoll: [Float] = []
    private var calibrationRMS: [Float] = []

    init(
        fixedThreshold: Float = Config.silenceThreshold,
        adaptive: Bool,
        preRollSampleLimit: Int = Int(Config.audioSampleRate * Config.preRollDuration)
    ) {
        self.threshold = fixedThreshold
        self.adaptive = adaptive
        self.preRollSampleLimit = preRollSampleLimit
    }

    /// Feeds one chunk of 16kHz samples with its RMS level. Returns true if the chunk is speech.
    mutating func feed(_ samples: [Float], rms: Float) -> Bool {
        // Adaptive mode: the first chunks measure the room. Keep their audio in the
        // pre-roll anyway, because the user may already be talking.
        if adaptive && calibrationRMS.count < calibrationChunkTarget {
            calibrationRMS.append(rms)
            if calibrationRMS.count == calibrationChunkTarget {
                threshold = Self.adaptedThreshold(from: calibrationRMS)
                print("[SpeechGate] Adaptive VAD calibrated: threshold=\(threshold)")
            }
            appendToPreRoll(samples)
            return false
        }

        let isSpeech = rms > threshold
        if isSpeech && !speechDetected {
            speechDetected = true
            kept.append(contentsOf: preRoll)
            preRoll.removeAll()
            print("[SpeechGate] Speech detected")
        }

        if speechDetected {
            kept.append(contentsOf: samples)
        } else {
            appendToPreRoll(samples)
        }
        return isSpeech
    }

    /// 1.5× the room's average level, kept between the minimum and maximum allowed thresholds.
    static func adaptedThreshold(from rmsValues: [Float]) -> Float {
        let average = rmsValues.reduce(0, +) / Float(max(rmsValues.count, 1))
        return min(max(average * 1.5, Config.minSilenceThreshold), Config.maxAdaptiveSilenceThreshold)
    }

    private mutating func appendToPreRoll(_ samples: [Float]) {
        preRoll.append(contentsOf: samples)
        if preRoll.count > preRollSampleLimit {
            preRoll.removeFirst(preRoll.count - preRollSampleLimit)
        }
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run the same command. Expected: `TEST SUCCEEDED`, 6 tests.

- [ ] **Step 5: Make `AudioRecorder` use `SpeechGate`**

In `AudioRecorder.swift`:

a) Replace:
```swift
    // Silence detection settings
    private let silenceThreshold: Float = Config.silenceThreshold
    private var silenceDuration: TimeInterval   // How long silence triggers stop
    private let maxDuration: TimeInterval = Config.maxRecordingDuration
    private let timeoutEnabled: Bool            // Whether to enforce maxDuration

    // Adaptive VAD
    private var adaptiveVADEnabled: Bool
    private var isCalibrating = false
    private var calibrationRMSValues: [Float] = []
    private var calibrationChunkCount = 0
    private let calibrationChunkTarget = 2  // 2 chunks × 100ms = 200ms
    private var adaptedThreshold: Float
```
with:
```swift
    // Silence detection settings
    private var silenceDuration: TimeInterval   // How long silence triggers stop
    private let maxDuration: TimeInterval = Config.maxRecordingDuration
    private let timeoutEnabled: Bool            // Whether to enforce maxDuration

    // Speech detection and which samples to keep (see SpeechGate)
    private let adaptiveVADEnabled: Bool
    private var gate: SpeechGate
```

b) Replace:
```swift
    private var isRecording = false
    private var audioBuffer: [Float] = []
    private var recordingStartTime: Date?
    private var lastSpeechTime: Date?
    private var speechDetected = false
```
with:
```swift
    private var isRecording = false
    private var recordingStartTime: Date?
    private var lastSpeechTime: Date?
```

c) In `init`, replace `        self.adaptedThreshold = Config.silenceThreshold` with `        self.gate = SpeechGate(adaptive: adaptiveVADEnabled)`.

d) In `startRecording()`, replace:
```swift
        // Reset state
        audioBuffer = []
        audioBuffer.reserveCapacity(Int(maxDuration * sampleRate))
        recordingStartTime = Date()
        lastSpeechTime = nil
        speechDetected = false
        isRecording = true

        // Reset adaptive VAD calibration
        isCalibrating = adaptiveVADEnabled
        calibrationRMSValues = []
        calibrationChunkCount = 0
        adaptedThreshold = Config.silenceThreshold
```
with:
```swift
        // Reset state
        gate = SpeechGate(adaptive: adaptiveVADEnabled)
        recordingStartTime = Date()
        lastSpeechTime = nil
        isRecording = true
```

e) In `stopRecording()`, replace:
```swift
        // Check if we got any audio
        if audioBuffer.isEmpty {
            onRecordingComplete?(.failure(.noAudioRecorded))
            return
        }

        let duration = Double(audioBuffer.count) / sampleRate
        onRecordingComplete?(.success(RecordingResult(duration: duration, audioData: audioBuffer)))
```
with:
```swift
        // Check if we got any audio
        let audioData = gate.kept
        if audioData.isEmpty {
            onRecordingComplete?(.failure(.noAudioRecorded))
            return
        }

        let duration = Double(audioData.count) / sampleRate
        onRecordingComplete?(.success(RecordingResult(duration: duration, audioData: audioData)))
```

f) In `cancelRecording()`, replace `        audioBuffer = []` with `        gate = SpeechGate(adaptive: adaptiveVADEnabled)`.

g) Replace the whole `processAudioBuffer` function, from `    /// Process incoming audio buffer` to its closing `    }`, with:

```swift
    /// Process incoming audio buffer
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        guard isRecording else { return }

        // Convert to our target format (16kHz mono)
        guard let convertedBuffer = AudioRecorder.convert(buffer, using: converter, to: targetFormat),
              let channelData = convertedBuffer.floatChannelData?[0] else {
            return
        }
        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        // Calculate audio level (RMS)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(frameLength))

        // Report audio level to UI
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(rms)
        }

        // Decide whether this is speech and which samples to keep
        let now = Date()
        if gate.feed(samples, rms: rms) {
            lastSpeechTime = now
        }

        // Check stopping conditions
        let elapsed = now.timeIntervalSince(recordingStartTime ?? now)

        // Stop if max duration reached (only if timeout is enabled)
        if timeoutEnabled && elapsed >= maxDuration {
            print("[AudioRecorder] Max duration reached")
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
            return
        }

        // Stop if silence after speech
        if gate.speechDetected, let lastSpeech = lastSpeechTime,
           now.timeIntervalSince(lastSpeech) >= silenceDuration {
            print("[AudioRecorder] Silence detected, stopping")
            DispatchQueue.main.async { [weak self] in
                self?.stopRecording()
            }
        }
    }
```

- [ ] **Step 6: Prove the old fields are gone, build, test and check by hand**

```bash
cd /Users/karthikvadlapatla/claude/rayee/swift/Rayee/Rayee
grep -nE "audioBuffer|isCalibrating|calibrationRMSValues|adaptedThreshold\b|speechDetected = " AudioRecorder.swift
```
Expected: no output.
Run the build and test commands. Expected: both succeed.
Manual check:
1. Turn on Settings → General → Adaptive silence detection.
2. Press the hotkey and **immediately** say "Testing one two three".
3. Expected: the transcript starts with "Testing".
4. Turn adaptive mode off and repeat, starting with a soft word like "Hello". Expected: "Hello" is there.

- [ ] **Step 7: Commit**

```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: keep 300ms of audio before speech and cap adaptive VAD threshold"
```

---

### Task 5: Give the user's clipboard back after auto-paste (F7)

**Files:**
- Modify: `swift/Rayee/Rayee/PasteManager.swift` (add `ClipboardSnapshot`, use it in `pasteText`)
- Modify: `swift/Rayee/Rayee/Config.swift` (one constant)
- Test: `swift/Rayee/RayeeTests/ClipboardSnapshotTests.swift` (new)

**Interfaces:**
- Produces: `struct ClipboardSnapshot { init(of pasteboard: NSPasteboard); func restore(to pasteboard: NSPasteboard) }`; `Config.clipboardRestoreDelay`.

- [ ] **Step 1: Write the failing test**

Create `swift/Rayee/RayeeTests/ClipboardSnapshotTests.swift`:

```swift
import XCTest
import AppKit
@testable import Rayee

final class ClipboardSnapshotTests: XCTestCase {

    private var board: NSPasteboard!

    override func setUp() {
        super.setUp()
        // A private pasteboard, so tests never touch the real clipboard
        board = NSPasteboard(name: NSPasteboard.Name("rayee-tests-\(UUID().uuidString)"))
        board.clearContents()
    }

    override func tearDown() {
        board.releaseGlobally()
        board = nil
        super.tearDown()
    }

    func testRestoresPlainText() {
        board.setString("my copied text", forType: .string)
        let snapshot = ClipboardSnapshot(of: board)

        board.clearContents()
        board.setString("dictated text", forType: .string)
        snapshot.restore(to: board)

        XCTAssertEqual(board.string(forType: .string), "my copied text")
    }

    func testRestoresNonTextData() {
        // Review focus: the user had an image on the clipboard.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        board.setData(png, forType: .png)
        let snapshot = ClipboardSnapshot(of: board)

        board.clearContents()
        board.setString("dictated text", forType: .string)
        snapshot.restore(to: board)

        XCTAssertEqual(board.data(forType: .png), png)
        XCTAssertNil(board.string(forType: .string))
    }

    func testEmptyClipboardStaysEmpty() {
        let snapshot = ClipboardSnapshot(of: board)

        board.setString("dictated text", forType: .string)
        snapshot.restore(to: board)

        XCTAssertNil(board.string(forType: .string))
        XCTAssertEqual(board.pasteboardItems?.count ?? 0, 0)
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run the test command with `-only-testing:RayeeTests/ClipboardSnapshotTests`.
Expected: the build fails with `cannot find 'ClipboardSnapshot' in scope`.

- [ ] **Step 3: Add `ClipboardSnapshot`**

At the end of `PasteManager.swift`, after the class's closing `}`, add:

```swift

/// A copy of everything on a pasteboard (text, images, files, rich text),
/// so it can be put back after Rayee borrows the clipboard to paste.
struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(of pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            return dataByType
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restoredItems = items.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dataByType {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
    }
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run the same command. Expected: `TEST SUCCEEDED`, 3 tests.

- [ ] **Step 5: Use it in `pasteText`**

In `Config.swift`, after `autoPasteDelay`, add:
```swift

    /// How long after pasting before the user's own clipboard is put back (seconds).
    /// Gives the target app time to read the pasted text first.
    static let clipboardRestoreDelay: TimeInterval = 0.5
```

In `PasteManager.swift`, `pasteText(_:)`, replace:
```swift
        // Step 1: Copy the text to the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Step 2: Small delay to ensure the clipboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulatePaste()
        }
```
with:
```swift
        // Step 1: Remember what the user had copied, then put our text on the clipboard
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        // Step 2: Small delay to ensure the clipboard is ready, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulatePaste()

            // Step 3: Give the user's clipboard back, unless something new was copied meanwhile
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.clipboardRestoreDelay) {
                if pasteboard.changeCount == ourChangeCount {
                    snapshot.restore(to: pasteboard)
                }
            }
        }
```

(The panel's **Copy** button uses its own code in `AppState.copyFromPanel()`. It deliberately leaves the text on the clipboard and isn't affected.)

- [ ] **Step 6: Build, run all tests, and check by hand**

Run the build and test commands. Expected: both succeed.
Manual check:
1. Copy a word in Notes (Cmd+C).
2. Click into a text field, dictate a sentence, and let it auto-paste.
3. Wait a second, then press Cmd+V somewhere else.
   Expected: the word you copied in step 1 is pasted, not the dictation.
4. Repeat with a screenshot copied to the clipboard (Cmd+Ctrl+Shift+4). Expected: the image pastes afterwards.
5. Try auto-paste in Slack or a browser text box too.
   Expected: the dictated text arrives there (not your old clipboard). If an app pastes the old clipboard instead, note the app in the Session log and raise `clipboardRestoreDelay` to 1.0.

- [ ] **Step 7: Commit**

```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: restore the user's clipboard after auto-paste"
```

---

### Task 6: Open the setup guide on first launch (F12)

**Files:**
- Modify: `swift/Rayee/Rayee/RayeeApp.swift` (menu bar label view)
- Modify: `swift/Rayee/Rayee/SimpleMenuView.swift` (remove the old trigger)

**Interfaces:** Produces `private struct MenuBarLabel: View` in `RayeeApp.swift`. Nothing else uses it.

No unit test is possible here: it's about when SwiftUI draws the menu bar icon. The check is manual.

- [ ] **Step 1: Move the first-launch check onto the menu bar icon**

In `RayeeApp.swift`, replace:
```swift
        } label: {
            Image(systemName: appState.menuBarIcon)
                .renderingMode(.template)
        }
```
with:
```swift
        } label: {
            MenuBarLabel(icon: appState.menuBarIcon)
        }
```

and add this after the `RayeeApp` struct's closing `}` (before `// MARK: - App Delegate`):

```swift

/// The menu bar icon. It also opens the setup guide on first launch: the icon is drawn
/// at launch, while the menu's contents only appear once the user clicks the icon.
private struct MenuBarLabel: View {
    let icon: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: icon)
            .renderingMode(.template)
            .onAppear {
                guard !SettingsManager.shared.hasCompletedSetup else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    openWindow(id: "setup-guide")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
    }
}
```

- [ ] **Step 2: Remove the old trigger from the menu**

In `SimpleMenuView.swift`:

a) Delete `    @State private var hasCheckedFirstLaunch = false`.

b) Replace:
```swift
        .keyboardShortcut("q", modifiers: .command)
        .onAppear {
            // Show setup guide on first launch
            if !hasCheckedFirstLaunch {
                hasCheckedFirstLaunch = true
                if !SettingsManager.shared.hasCompletedSetup {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        openWindow(id: "setup-guide")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
```
with:
```swift
        .keyboardShortcut("q", modifiers: .command)
```

- [ ] **Step 3: Build and check by hand**

Run the build command. Expected: `BUILD SUCCEEDED`.
Manual check:
1. Quit Rayee and run `defaults delete com.rayee.app hasCompletedSetup`.
2. Run from Xcode (Cmd+R) and **don't click the menu bar icon**.
3. Expected: the System Status window opens by itself within about a second.
4. Click **Done**, quit, and run again. Expected: it does **not** open.

If step 3 fails (the label's `onAppear` doesn't fire in a menu bar extra), **don't** improvise a workaround. Revert this task (`git checkout -- swift/Rayee/Rayee/RayeeApp.swift swift/Rayee/Rayee/SimpleMenuView.swift`), write what happened in the Session log, and ask the user.

- [ ] **Step 4: Run all tests and commit**

Run the test command. Expected: `TEST SUCCEEDED`.
```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: open the setup guide on first launch without needing a menu click"
```

---

### Task 7: Smart Dictation saves the cleaned text, and Discard really stops it (F13, F14)

**Files:**
- Modify: `swift/Rayee/Rayee/TranscriptionCoordinator.swift` (add `SmartDictationPolicy`, hold the history save)
- Modify: `swift/Rayee/Rayee/AppState.swift` (save after clean-up, make the transform cancellable)
- Modify: `swift/Rayee/Rayee/MLXTransformManager.swift` (honour cancellation)
- Test: `swift/Rayee/RayeeTests/SmartDictationPolicyTests.swift` (new)

**Interfaces:**
- Consumes: `HistoryManager.saveTranscription(text:model:originalText:transformations:)` (already exists); `TransformationType.smartDictation.rawValue == "smartDictation"`.
- Produces: `enum SmartDictationPolicy { static func willRun(smartDictationEnabled: Bool, transformationsEnabled: Bool, text: String) -> Bool }`. `MLXTransformManager.streamTransform` now throws `CancellationError` when its task is cancelled.

- [ ] **Step 1: Write the failing test**

Create `swift/Rayee/RayeeTests/SmartDictationPolicyTests.swift`:

```swift
import XCTest
@testable import Rayee

final class SmartDictationPolicyTests: XCTestCase {

    func testRunsWhenBothSwitchesAreOnAndThereIsText() {
        XCTAssertTrue(SmartDictationPolicy.willRun(
            smartDictationEnabled: true, transformationsEnabled: true, text: "um hello"))
    }

    func testDoesNotRunWhenSmartDictationIsOff() {
        XCTAssertFalse(SmartDictationPolicy.willRun(
            smartDictationEnabled: false, transformationsEnabled: true, text: "um hello"))
    }

    func testDoesNotRunWhenTransformationsAreOff() {
        XCTAssertFalse(SmartDictationPolicy.willRun(
            smartDictationEnabled: true, transformationsEnabled: false, text: "um hello"))
    }

    func testDoesNotRunOnEmptyText() {
        XCTAssertFalse(SmartDictationPolicy.willRun(
            smartDictationEnabled: true, transformationsEnabled: true, text: ""))
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run the test command with `-only-testing:RayeeTests/SmartDictationPolicyTests`.
Expected: the build fails with `cannot find 'SmartDictationPolicy' in scope`.

- [ ] **Step 3: Add the policy and hold the early history save**

In `TranscriptionCoordinator.swift`, add this after the `UserFacingError` enum:

```swift

/// Whether Smart Dictation will clean up a transcription automatically.
/// TranscriptionCoordinator (to hold the history save) and AppState (to start the clean-up)
/// both use it, so the two can never disagree.
enum SmartDictationPolicy {
    static func willRun(smartDictationEnabled: Bool, transformationsEnabled: Bool, text: String) -> Bool {
        smartDictationEnabled && transformationsEnabled && !text.isEmpty
    }
}
```

In `handleTranscriptionSuccess`, replace:
```swift
        // Save to history if we got text
        if !text.isEmpty {
            historyManager.saveTranscription(
                text: text,
                model: settings.selectedWhisperKitModel
            )
        }

        // Determine if we should and can paste
        var didPaste = false
        pendingSmartDictationPaste = false
        if pendingAutoPaste && settings.autoPasteEnabled && !text.isEmpty {
            if PasteTargetDetector.hasValidPasteTarget() {
                if settings.smartDictationEnabled && settings.transformationsEnabled {
```
with:
```swift
        let smartDictationWillRun = SmartDictationPolicy.willRun(
            smartDictationEnabled: settings.smartDictationEnabled,
            transformationsEnabled: settings.transformationsEnabled,
            text: text
        )

        // Save to history now, unless Smart Dictation is about to clean the text up.
        // In that case AppState saves the final text when the clean-up ends.
        if !text.isEmpty && !smartDictationWillRun {
            historyManager.saveTranscription(
                text: text,
                model: settings.selectedWhisperKitModel
            )
        }

        // Determine if we should and can paste
        var didPaste = false
        pendingSmartDictationPaste = false
        if pendingAutoPaste && settings.autoPasteEnabled && !text.isEmpty {
            if PasteTargetDetector.hasValidPasteTarget() {
                if smartDictationWillRun {
```

- [ ] **Step 4: Run the test to confirm it passes**

Run the same command. Expected: `TEST SUCCEEDED`, 4 tests.

- [ ] **Step 5: Make the model stop when its task is cancelled**

In `MLXTransformManager.swift`, `streamTransform`, replace:
```swift
        for await generation in stream {
            if case .chunk(let token) = generation {
                onToken(token)
            }
        }
    }
```
with:
```swift
        for await generation in stream {
            try Task.checkCancellation()
            if case .chunk(let token) = generation {
                onToken(token)
            }
        }
        // The stream also ends early when the task is cancelled. Report that as a cancellation, not a result.
        try Task.checkCancellation()
    }
```

- [ ] **Step 6: Save after clean-up and cancel on Discard/Done in `AppState.swift`**

a) After `    private var cancellables = Set<AnyCancellable>()`, add:
```swift

    /// The transformation currently streaming, so it can be stopped if the panel is dismissed
    private var transformTask: Task<Void, Never>?
```

b) In `startTranscription(autoPaste:)`, after `        errorMessage = nil`, add `        cancelTransformation()`.

c) Replace:
```swift
        recordingPanelController.onDone = { [weak self] in
            self?.recordingPanelController.hidePanel()
        }
        recordingPanelController.onDiscard = { [weak self] in
            self?.recordingPanelController.hidePanel()
        }
```
with:
```swift
        recordingPanelController.onDone = { [weak self] in
            self?.cancelTransformation()
            self?.recordingPanelController.hidePanel()
        }
        recordingPanelController.onDiscard = { [weak self] in
            self?.cancelTransformation()
            self?.recordingPanelController.hidePanel()
        }
```

d) In `handleTranscriptionResult`, replace:
```swift
                let settings = SettingsManager.shared
                if settings.smartDictationEnabled && settings.transformationsEnabled {
```
with:
```swift
                let settings = SettingsManager.shared
                if SmartDictationPolicy.willRun(
                    smartDictationEnabled: settings.smartDictationEnabled,
                    transformationsEnabled: settings.transformationsEnabled,
                    text: text
                ) {
```

e) Replace the whole `handleTransformation(type:thenPaste:)` function, from its `///` doc comment to its closing `    }`, with:

```swift
    /// Handle a transformation request from the recording panel.
    /// When thenPaste is true, automatically pastes the result and hides the panel on completion.
    private func handleTransformation(type: TransformationType, thenPaste: Bool = false) {
        let rawText = recordingPanelController.transcribedText
        guard !rawText.isEmpty else { return }

        let transformState = recordingPanelController.transformState
        transformState.startTransformation(text: rawText, type: type)
        recordingPanelController.updateWindowSizeForTransform()

        cancelTransformation()
        transformTask = Task { @MainActor in
            var cleanedText: String?
            do {
                try await MLXTransformManager.shared.streamTransform(
                    text: rawText,
                    type: type,
                    onToken: { [weak self] token in
                        transformState.appendStreamingToken(token)
                        self?.recordingPanelController.updateWindowSizeForTransform()
                    }
                )
                let result = transformState.streamingText
                if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // LLM produced nothing — treat as failure and keep raw text
                    transformState.failTransformation(message: "No output produced")
                    recordingPanelController.updateWindowSizeForTransform()
                    if thenPaste { pasteAndHidePanel(rawText) }
                } else {
                    cleanedText = result
                    transformState.completeTransformation(transformedText: result)
                    recordingPanelController.updateWindowSizeForTransform()
                    if thenPaste { pasteAndHidePanel(result) }
                }
            } catch is CancellationError {
                // The panel was dismissed mid-way: it's already reset, and nothing should be pasted.
            } catch {
                transformState.failTransformation(message: error.localizedDescription)
                recordingPanelController.updateWindowSizeForTransform()
                if thenPaste { pasteAndHidePanel(rawText) }
            }

            if type == .smartDictation {
                saveSmartDictationHistory(raw: rawText, cleaned: cleanedText)
            }
        }
    }

    /// Stops any transformation still streaming (for example, the panel was dismissed)
    private func cancelTransformation() {
        transformTask?.cancel()
        transformTask = nil
    }

    /// Smart Dictation holds back the history save until the clean-up ends.
    /// Saves the cleaned text (with the original), or just the original if the clean-up didn't finish.
    private func saveSmartDictationHistory(raw: String, cleaned: String?) {
        let model = SettingsManager.shared.selectedWhisperKitModel
        if let cleaned {
            HistoryManager.shared.saveTranscription(
                text: cleaned,
                model: model,
                originalText: raw,
                transformations: TransformationType.smartDictation.rawValue
            )
        } else {
            HistoryManager.shared.saveTranscription(text: raw, model: model)
        }
    }
```

f) In `cancelRecording()`, before `        transcriptionCoordinator.cancel()`, add `        cancelTransformation()`.

- [ ] **Step 7: Build, run all tests, and check by hand**

Run the build and test commands. Expected: both succeed.
Manual check (Settings → Transforms → turn on "Auto-clean after transcription"; auto-paste on):
1. Click into a Notes document and dictate: "um so I think we should uh meet tomorrow".
   Expected: cleaned text is pasted. In Settings → History, the newest entry shows the **cleaned** text with a Smart Dictation tag.
2. Dictate a long paragraph. While the panel is still writing the cleaned version, press **Discard**.
   Expected: nothing is pasted into Notes, the panel closes, and History has the **original** text.
3. Turn Smart Dictation off and dictate once.
   Expected: History saves the text exactly once (no duplicate).

- [ ] **Step 8: Commit**

```bash
cd /Users/karthikvadlapatla/claude/rayee
git add -A swift/Rayee docs/plans
git commit -m "fix: Smart Dictation saves cleaned text to history and stops on Discard"
```

---

### Task 8: Full check and release v0.8

**Files:**
- Modify: `docs/plans/2026-10-15-00-improvement-roadmap.md` (status, log)
- Modify: `ROADMAP.md` (completed work)

- [ ] **Step 1: Run every test**

Run the test command. Expected: `TEST SUCCEEDED`.
The test classes are `MLXTransformManagerTests`, `WhisperKitManagerTests`, `TransformErrorMessageTests`, `UserFacingErrorTests`, `RecordingLimitsTests`, `AudioConversionTests`, `SpeechGateTests`, `ClipboardSnapshotTests` and `SmartDictationPolicyTests`.

- [ ] **Step 2: Hands-on check with the user (about 10 minutes)**

Go through this with the user in the app built from Xcode, ticking each item:
- [ ] Dictate a sentence into Notes. It stops by itself after about 2 s and pastes correctly.
- [ ] Dictate for about 90 seconds. All of it is transcribed (the old limit was 60 s).
- [ ] Your clipboard (a copied word, then an image) is back after auto-paste.
- [ ] With adaptive detection on, start talking instantly. The first word is kept.
- [ ] Each of the five Format options (Grammar, Bullets, Rephrase, Formal, Casual) still works from the result panel.
- [ ] Smart Dictation on: cleaned text is pasted and saved in History. Discard mid-way pastes nothing.
- [ ] With the microphone denied, the panel explains the problem. (Re-allow it afterwards.)
- [ ] Changing the hotkey updates the panel hint.
- [ ] Settings → General has no "Fast transcription mode".

Write any failures in the Session log and fix them before going on.

- [ ] **Step 3: Update docs**

- `ROADMAP.md`: add a "Completed: v0.8 reliability release" section with 3–5 plain bullets taken from the checklist above.
- Roadmap master file: set Phase 2's status to `Done` and add a Session log entry.

```bash
cd /Users/karthikvadlapatla/claude/rayee
git add ROADMAP.md docs/plans
git commit -m "docs: record v0.8 reliability work"
```

- [ ] **Step 4: CONFIRM WITH USER, then release**

Ask the user: "Everything checks out. Should I publish v0.8? That creates a public GitHub release, and everyone's app will offer the update." Only on a clear yes, merge `release/v0.8` into `main` the way earlier releases were (through a PR), then run the `/publish-release` skill for version 0.8.
