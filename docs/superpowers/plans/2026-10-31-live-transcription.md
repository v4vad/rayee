# Live Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While the user dictates, show their words in the notch recorder about a second after they speak them. Draft words are grey and settled words are solid. The pasted text still comes from Whisper, unchanged.

**Architecture:**
- A new `LiveTranscriber` wraps Apple's `SpeechAnalyzer` + `SpeechTranscriber` (Speech framework, macOS 26). It gets the audio `AudioRecorder` already records through a new tap placed **before** the speech gate. It converts each buffer to `SpeechAnalyzer.bestAvailableAudioFormat` (16 kHz mono Int16), because Float32 crashes the process.
- A pure value type, `LiveTranscript`, holds the settled and draft text. It also decides which tail of the text is visible, so the merging and trimming can be unit-tested.
- `TranscriptionCoordinator` starts and stops the transcriber alongside the recording and passes `LiveTranscript` updates to `AppState`. `AppState` hands them to `RecorderController`, which holds the transcript **beside** `RecorderPhase` (not inside it), so existing phase comparisons are untouched. The listening body grows one line at a time, to at most 3 lines, and never shrinks while recording.
- A Settings switch and a "Preview language" menu live in Settings → Recording. `LivePreviewLanguages` is an `ObservableObject` that lists the supported languages, reserves the chosen one, releases the old one, and downloads it with progress.
- Every live-text failure is silent. Recording, transcription and paste never wait on the transcriber, and never fail because of it.

**Tech Stack:** Swift 5 mode, SwiftUI + AppKit, `Speech` (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, `AnalyzerInput`), `AVFoundation` (`AVAudioConverter`), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-18-live-transcription-design.md` (binding). Research and measured API behaviour: `docs/brainstorms/2026-10-17-live-transcription-engines.md`. Working API usage to copy from: `.superpowers/spikes/live-transcription/spike.swift` (git-ignored, on this Mac only).

## Global Constraints

- Minimum macOS **26.0**. No `#available` checks. Pure native Swift, **no new packages**.
- Swift: 4-space indent, no tabs, SwiftUI for all views. Match the surrounding comment style (short `///` doc comments, `// MARK: -` sections).
- **App source files are listed by hand in `project.pbxproj`.** Add them with `python3 -I scripts/xcodeproj_files.py add <Name>.swift`, run from the repo root, after creating the file. Test files in `swift/Rayee/RayeeTests/` need nothing.
- Settings go through `SettingsManager` (UserDefaults). Audio Rayee records stays 16 kHz mono Float32. Only the copy sent to Apple's recognizer is converted.
- **Never push Float32 audio to `SpeechAnalyzer`.** Always convert to `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`.
- **Nothing in the stop, paste or cancel path awaits the transcriber.** Tear it down fire-and-forget.
- **A live-text failure never shows an error, plays a sound or changes the recorder's phase.** It is logged with `AppLogger.log(_, category: "live")` and the preview just doesn't appear.
- **Pauses never end a recording.** Don't touch `SpeechGate`, silence auto-stop or `Config` timings.
- The pasted text, Smart Dictation, Vocabulary and History must not change. `WhisperKitManager` is not modified.
- Preset: `.timeIndexedProgressiveTranscription` (the one the spike measured).
- Live text: at most **3 lines**, width unchanged (300 pt body), grows one line at a time, never shrinks while recording. Draft words `.white.opacity(0.45)`, settled words `.white.opacity(0.9)`. 13 pt system font, like the Result text.
- Setting copy (exact): switch **"Show words while I speak"**, on by default. Menu **"Preview language"**, default **`en-IN`** (English (India)).
- At most 5 reserved languages (`AssetInventory.maximumReservedLocales`). Rayee reserves only the chosen one and releases any other it holds.
- Don't add a speech-recognition permission prompt. If Apple's recognizer reports an authorization error at runtime, **stop and report it to the user** (Task 5). Don't work around it.
- Paths are relative to the repo root `/Users/karthikvadlapatla/claude/rayee`. Run every command from there.
- **Build:** `xcodebuild build -project swift/Rayee/Rayee.xcodeproj -scheme Rayee -destination 'platform=macOS' -derivedDataPath swift/Rayee/build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
- **Test:** `xcodebuild test -project swift/Rayee/Rayee.xcodeproj -scheme Rayee -destination 'platform=macOS' -derivedDataPath swift/Rayee/build 2>&1 | grep -E "error:|Test Case.*failed|TEST (SUCCEEDED|FAILED)"`. `** TEST SUCCEEDED **` is the pass signal (there is no "Executed N tests" line). To run one class, add `-only-testing:RayeeTests/<ClassName>` before `2>&1`.
- Logs and temporary files go in `swift/Rayee/build/` (git-ignored), never `/tmp` or `$HOME`.
- **Commits:** never commit `.session/`, `build/`, `.env` or keys. Every commit message ends with exactly these two lines, after a blank line:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01DrxXknrX9QbUgriKhdxVoq
  ```
- The user is not a developer. Report in plain language.

## Review Focus

These are the inputs the spec implies that are most likely to hurt a real user, and that no feature test covers on its own.

1. **A late result from a recording that already ended must not reappear,** either in the next recording or in "Transcribing". The recorder ignores transcripts unless the phase is `.listening`, and the coordinator drops callbacks from a transcriber that isn't the current one. *Task 1: `testUpdatesOutsideListeningAreIgnored` (pure rule). Task 4: the identity guard, checked by hand in Task 5.*
2. **A draft that gets shorter or is rewritten must not make the recorder shrink or jump.** *Task 1: `testLiveLinesNeverShrink`.*
3. **A very long unbroken stretch of draft text** (a 1-minute sentence with no pause, where everything stays grey) must show only its tail, cut at a word boundary, not the start. *Task 1: `testVisibleTailKeepsTheEndAtAWordBoundary`, `testVisibleTailSplitsAcrossSettledAndDraft`.*
4. **A chosen language that this Mac no longer supports, or isn't installed yet,** must leave dictation exactly as today, with no error and no stuck preview. *Task 2: `testUnsupportedOrMissingLanguageSkipsThePreview` (the pure gate). Task 5: checked by hand.*
5. **Esc or a silence auto-stop while Apple's recognizer is still starting up** (the first ~1 s) must not hang or crash. The transcriber stops before it has finished preparing. *Task 2: `testStopBeforeStartIsSafe`, `testStopTwiceIsSafe`. Task 5: checked by hand.*

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `swift/Rayee/Rayee/LiveTranscript.swift` | create (T1) | `LiveTranscript` value: merge results, visible tail |
| `swift/Rayee/Rayee/RecorderState.swift` | modify (T1) | `RecorderLayout.bodyHeight(for:liveLines:)`, `RecorderLayout.liveLines(previous:transcript:)`, `RecorderRules.acceptsLiveTranscript(in:)` |
| `swift/Rayee/Rayee/LiveTranscriber.swift` | create (T2) | `LiveTranscriber`: Apple recognizer session, buffer conversion, start/stop |
| `swift/Rayee/Rayee/AudioRecorder.swift` | modify (T2) | `onRawBuffer` tap before the speech gate |
| `swift/Rayee/Rayee/SettingsManager.swift` | modify (T3) | `livePreviewEnabled`, `livePreviewLanguage` |
| `swift/Rayee/Rayee/LivePreviewLanguages.swift` | create (T3) | supported list, reserve/release, download progress |
| `swift/Rayee/Rayee/RecordingSettingsTab.swift` | modify (T3) | switch, menu, progress, unsupported note |
| `swift/Rayee/Rayee/TranscriptionCoordinator.swift` | modify (T4) | start/stop the transcriber with the recording, `onLiveTranscript` |
| `swift/Rayee/Rayee/AppState.swift` | modify (T4) | forward transcripts to the recorder |
| `swift/Rayee/Rayee/RecorderController.swift` | modify (T4) | hold `liveTranscript` + `liveLines`, `bodyHeight` used by view and hit-testing |
| `swift/Rayee/Rayee/RecorderView.swift` | modify (T4) | live text under the listening row |
| `swift/Rayee/RayeeTests/LiveTranscriptTests.swift`, `LiveTranscriberTests.swift` | create (T1, T2) | tests |
| `ROADMAP.md`, `README.md`, `docs/plans/2026-10-15-00-improvement-roadmap.md` | modify (T6) | docs, hands-on checks, session log |

---

### Task 1: Live transcript model and recorder layout

**Files:**
- Create: `swift/Rayee/Rayee/LiveTranscript.swift`
- Modify: `swift/Rayee/Rayee/RecorderState.swift:75-128`
- Test: `swift/Rayee/RayeeTests/LiveTranscriptTests.swift`

**Interfaces:**
- Produces:
  - `struct LiveTranscript: Equatable { private(set) var settled: String; private(set) var draft: String; var isEmpty: Bool; var text: String /* settled + draft */; mutating func apply(_ text: String, isFinal: Bool); func visibleTail(maxCharacters: Int) -> (settled: String, draft: String) }`
  - `RecorderLayout.maxLiveLines = 3`
  - `RecorderLayout.bodyHeight(for phase: RecorderPhase, liveLines: Int = 0) -> CGFloat`
  - `RecorderLayout.liveLines(previous: Int, transcript: LiveTranscript) -> Int`
  - `RecorderRules.acceptsLiveTranscript(in phase: RecorderPhase) -> Bool`

- [ ] **Step 1: Write the failing tests** in `LiveTranscriptTests.swift`

```swift
import XCTest
@testable import Rayee

final class LiveTranscriptTests: XCTestCase {

    // MARK: - Merging results

    func testDraftReplacesTheLastDraft() {
        var t = LiveTranscript()
        t.apply("Hello", isFinal: false)
        t.apply("Hello there", isFinal: false)
        XCTAssertEqual(t.settled, "")
        XCTAssertEqual(t.draft, "Hello there")
    }

    func testFinalSettlesAndClearsTheDraft() {
        var t = LiveTranscript()
        t.apply("Hello ther", isFinal: false)
        t.apply("Hello there.", isFinal: true)
        t.apply(" How", isFinal: false)
        XCTAssertEqual(t.settled, "Hello there.")
        XCTAssertEqual(t.draft, " How")
        XCTAssertEqual(t.text, "Hello there. How")
    }

    func testEmptyUntilWordsArrive() {
        var t = LiveTranscript()
        XCTAssertTrue(t.isEmpty)
        t.apply("  ", isFinal: false)
        XCTAssertTrue(t.isEmpty)   // whitespace alone shows nothing
    }

    // MARK: - Visible tail

    func testShortTextIsShownWhole() {
        var t = LiveTranscript()
        t.apply("Hi.", isFinal: true)
        t.apply(" there", isFinal: false)
        let tail = t.visibleTail(maxCharacters: 108)
        XCTAssertEqual(tail.settled, "Hi.")
        XCTAssertEqual(tail.draft, " there")
    }

    func testVisibleTailKeepsTheEndAtAWordBoundary() {
        var t = LiveTranscript()
        t.apply("alpha bravo charlie delta", isFinal: false)
        let tail = t.visibleTail(maxCharacters: 15)
        XCTAssertEqual(tail.settled, "")
        XCTAssertEqual(tail.draft, "charlie delta")   // never a cut-off "o charlie delta"
    }

    func testVisibleTailSplitsAcrossSettledAndDraft() {
        var t = LiveTranscript()
        t.apply("one two three four.", isFinal: true)
        t.apply(" five six", isFinal: false)
        let tail = t.visibleTail(maxCharacters: 17)
        XCTAssertEqual(tail.settled, "four.")
        XCTAssertEqual(tail.draft, " five six")
    }

    // MARK: - Layout

    func testListeningGrowsByOneLineAtATimeUpToThree() {
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 0), 44)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 1), 74)   // 44 + 18 + 12
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 3), 110)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 9), 110)
        XCTAssertLessThanOrEqual(RecorderLayout.bodyHeight(for: .listening, liveLines: 3), RecorderLayout.maxBodyHeight)
    }

    func testLiveLinesOnlyAffectListening() {
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .transcribing, liveLines: 3), 44)
        XCTAssertEqual(RecorderLayout.bodyHeight(for: .pasted, liveLines: 3), 44)
    }

    func testLiveLinesNeverShrink() {
        var t = LiveTranscript()
        t.apply(String(repeating: "word ", count: 20), isFinal: false)   // 100 chars → 3 lines
        XCTAssertEqual(RecorderLayout.liveLines(previous: 0, transcript: t), 3)
        t.apply("short", isFinal: false)                                  // draft rewritten shorter
        XCTAssertEqual(RecorderLayout.liveLines(previous: 3, transcript: t), 3)
        XCTAssertEqual(RecorderLayout.liveLines(previous: 0, transcript: LiveTranscript()), 0)
    }

    func testUpdatesOutsideListeningAreIgnored() {
        XCTAssertTrue(RecorderRules.acceptsLiveTranscript(in: .listening))
        for phase: RecorderPhase in [.hidden, .transcribing, .cleaningUp, .pasted,
                                     .result(text: "x"), .error(message: "x", action: nil)] {
            XCTAssertFalse(RecorderRules.acceptsLiveTranscript(in: phase), "\(phase)")
        }
    }
}
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run the Test command with `-only-testing:RayeeTests/LiveTranscriptTests`.
Expected: build errors, "cannot find 'LiveTranscript' in scope".

- [ ] **Step 3: Implement**
  - Create `LiveTranscript.swift`, then run `python3 -I scripts/xcodeproj_files.py add LiveTranscript.swift`.
  - `apply`: a final result appends `text` to `settled` and clears `draft`. A draft result replaces `draft`.
  - `isEmpty` is true when `text` is whitespace only.
  - `visibleTail`: if `text.count <= maxCharacters`, return both parts unchanged. Otherwise take the last `maxCharacters` characters of `text`, then drop everything up to and including the first space (if there is one), so no word is cut. Split the result back into a settled part and a draft part at the original boundary, and trim leading whitespace from the settled part only.
  - In `RecorderState.swift`:
    - Add `static let maxLiveLines = 3` and a private `liveTextPadding: CGFloat = 12` (gap below the text).
    - `bodyHeight(for:liveLines:)`: for `.listening` with `liveLines > 0`, return `compactHeight + lineHeight * min(liveLines, maxLiveLines) + liveTextPadding`. Every other case is unchanged. Keep the default argument, so existing callers and tests still compile.
    - `liveLines(previous:transcript:)`: return `previous` when the transcript is empty. Otherwise return `max(previous, estimatedLines(transcript.text, max: maxLiveLines))`.
    - `RecorderRules.acceptsLiveTranscript(in:)`: true only for `.listening`.

- [ ] **Step 4: Run the tests.** Run the Test command with no filter.
Expected: `** TEST SUCCEEDED **`, and the existing `RecorderStateTests` still pass.

- [ ] **Step 5: Commit**

```bash
git add swift/Rayee/Rayee/LiveTranscript.swift swift/Rayee/Rayee/RecorderState.swift swift/Rayee/RayeeTests/LiveTranscriptTests.swift swift/Rayee/Rayee.xcodeproj/project.pbxproj
git commit -m "feat: live transcript model and recorder layout"
```

---

### Task 2: LiveTranscriber and the audio tap

**Files:**
- Create: `swift/Rayee/Rayee/LiveTranscriber.swift`
- Modify: `swift/Rayee/Rayee/AudioRecorder.swift:58-60` (callback) and `:241-263` (`processAudioBuffer`)
- Test: `swift/Rayee/RayeeTests/LiveTranscriberTests.swift`

**Interfaces:**
- Consumes: `LiveTranscript` (Task 1); `AudioRecorder.convert(_:using:to:)` (existing, `AudioRecorder.swift:210`).
- Produces:
  - `AudioRecorder.onRawBuffer: ((AVAudioPCMBuffer) -> Void)?`. Called on the audio thread with every converted 16 kHz mono Float32 buffer, **before** `gate.feed`, from the first buffer onwards, silence included. The buffer is freshly allocated per call, so the receiver may keep it.
  - `final class LiveTranscriber`:
    - `init(languageIdentifier: String)`
    - `var onTranscript: ((LiveTranscript) -> Void)?`: always called on the main thread.
    - `func start()`: returns immediately; the setup runs in a `Task`.
    - `func append(_ buffer: AVAudioPCMBuffer)`: thread-safe, never blocks, callable before `start()` finishes.
    - `func stop()`: fire-and-forget, idempotent, safe before or during start.
  - `enum LivePreviewGate { static func shouldRun(isAvailable: Bool, supportedLocale: Locale?, installed: Bool) -> Bool }`
  - `extension LiveTranscriber { static func convertForAnalyzer(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? }`: a thin wrapper over `AudioRecorder.convert`, so the conversion can be tested.

- [ ] **Step 1: Write the failing tests** in `LiveTranscriberTests.swift`

```swift
import XCTest
import AVFoundation
@testable import Rayee

final class LiveTranscriberTests: XCTestCase {

    private let rayeeFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let analyzerFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!

    func testFloatAudioBecomesInt16AtTheSameRate() {
        let input = AVAudioPCMBuffer(pcmFormat: rayeeFormat, frameCapacity: 1_600)!
        input.frameLength = 1_600
        for i in 0..<1_600 { input.floatChannelData![0][i] = 0.5 }
        let converter = AVAudioConverter(from: rayeeFormat, to: analyzerFormat)!

        let output = LiveTranscriber.convertForAnalyzer(input, using: converter, to: analyzerFormat)

        XCTAssertEqual(output?.format.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(output?.format.sampleRate, 16_000)
        XCTAssertEqual(output?.frameLength, 1_600)
        XCTAssertEqual(Int(output!.int16ChannelData![0][800]), 16_384, accuracy: 2)
    }

    func testUnsupportedOrMissingLanguageSkipsThePreview() {
        let en = Locale(identifier: "en-IN")
        XCTAssertTrue(LivePreviewGate.shouldRun(isAvailable: true, supportedLocale: en, installed: true))
        XCTAssertFalse(LivePreviewGate.shouldRun(isAvailable: false, supportedLocale: en, installed: true))
        XCTAssertFalse(LivePreviewGate.shouldRun(isAvailable: true, supportedLocale: nil, installed: true))
        XCTAssertFalse(LivePreviewGate.shouldRun(isAvailable: true, supportedLocale: en, installed: false))
    }

    func testStopBeforeStartIsSafe() {
        let transcriber = LiveTranscriber(languageIdentifier: "en-IN")
        transcriber.stop()
        transcriber.append(AVAudioPCMBuffer(pcmFormat: rayeeFormat, frameCapacity: 160)!)
        transcriber.start()   // after stop: must do nothing and never call onTranscript
    }

    func testStopTwiceIsSafe() {
        let transcriber = LiveTranscriber(languageIdentifier: "en-IN")
        transcriber.start()
        transcriber.stop()
        transcriber.stop()
    }
}
```

- [ ] **Step 2: Run the tests to make sure they fail**

Run the Test command with `-only-testing:RayeeTests/LiveTranscriberTests`.
Expected: build errors, "cannot find 'LiveTranscriber' in scope".

- [ ] **Step 3: Add the tap to `AudioRecorder`**
  - Add `var onRawBuffer: ((AVAudioPCMBuffer) -> Void)?` next to `onAudioLevel`.
  - In `processAudioBuffer`, call `onRawBuffer?(convertedBuffer)` right after the `frameLength > 0` guard, before computing RMS.
  - Don't change anything else in the file.

- [ ] **Step 4: Implement `LiveTranscriber`** in `LiveTranscriber.swift` (then run `python3 -I scripts/xcodeproj_files.py add LiveTranscriber.swift`).
  - Copy API usage from `.superpowers/spikes/live-transcription/spike.swift` (`run(...)`, lines 36–135).
  - **Buffering before setup finishes:** in `init`, create `AsyncStream<AVAudioPCMBuffer>.makeStream()` for raw Float32 buffers. `append` only calls `continuation.yield(buffer)`, so early audio is held by the stream and never lost. Use `.bufferingNewest(600)` (about 60 s of 100 ms buffers) so a stalled recognizer can't grow memory without limit.
  - **`start()`** launches one `Task`, and that task does the following in order:
    1. Return early if already stopped.
    2. Run `SpeechTranscriber.supportedLocale(equivalentTo:)` on the chosen language, then create `SpeechTranscriber(locale:preset: .timeIndexedProgressiveTranscription)`.
    3. Check `AssetInventory.status(forModules:) == .installed`, and gate the run with `LivePreviewGate.shouldRun`. The preview **never** starts a download.
    4. Get the target format from `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`. If it's nil, stop.
    5. Create an `AVAudioConverter` from the Rayee format (16 kHz mono Float32) to the target format.
    6. Create a second `AsyncStream<AnalyzerInput>`, then `SpeechAnalyzer(modules:)`, `prepareToAnalyze(in:)`, `start(inputSequence:)`.
    7. Run a child task that reads `transcriber.results`, calls `transcript.apply(String(result.text.characters), isFinal: result.isFinal)`, and posts a copy to `onTranscript` on the main thread.
    8. Loop over the raw stream: convert each buffer with `convertForAnalyzer` and yield an `AnalyzerInput(buffer:)`.
  - **`stop()`** is guarded by a lock-protected `isStopped` flag. It finishes the raw continuation, cancels the tasks, and runs `Task { await analyzer?.cancelAndFinishNow() }`, which is never awaited by the caller. After `stop()`, `onTranscript` must never fire. Check the flag on the main thread before calling it.
  - **Errors:** any thrown error is logged once with `AppLogger.log("Live preview off: \(error)", category: "live")`, and then the transcriber stops itself. If the error mentions authorization or permission, log `"Live preview needs speech-recognition permission"` instead, so Task 5 can spot it.
  - **Temporary measurement log (removed in Task 6):** log `"Live first words after X.XX s"` the first time a non-empty result arrives, measured from `init`.

- [ ] **Step 5: Run the tests.** Run the Test command with no filter.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add swift/Rayee/Rayee/LiveTranscriber.swift swift/Rayee/Rayee/AudioRecorder.swift swift/Rayee/RayeeTests/LiveTranscriberTests.swift swift/Rayee/Rayee.xcodeproj/project.pbxproj
git commit -m "feat: LiveTranscriber wraps Apple's speech recognizer"
```

---

### Task 3: Settings: switch and preview language

**Files:**
- Modify: `swift/Rayee/Rayee/SettingsManager.swift` (keys `:15-33`, properties after `transformModel`, `init`, `resetToDefaults`)
- Create: `swift/Rayee/Rayee/LivePreviewLanguages.swift`
- Modify: `swift/Rayee/Rayee/RecordingSettingsTab.swift`
- Test: add to `swift/Rayee/RayeeTests/LiveTranscriberTests.swift`

**Interfaces:**
- Produces:
  - `SettingsKey.livePreviewEnabled = "livePreviewEnabled"`, `SettingsKey.livePreviewLanguage = "livePreviewLanguage"`
  - `SettingsManager.livePreviewEnabled: Bool` (default `true`), `SettingsManager.livePreviewLanguage: String` (BCP-47, default `LivePreviewLanguages.defaultIdentifier`)
  - `final class LivePreviewLanguages: ObservableObject`:
    - `static let defaultIdentifier = "en-IN"`
    - `@Published private(set) var options: [LanguageOption]`
    - `@Published private(set) var isAvailable: Bool`
    - `@Published private(set) var downloadProgress: Double?`: nil means not downloading, 0 means started but not measurable.
    - `func load() async`
    - `func choose(_ identifier: String) async`
  - `struct LanguageOption: Identifiable, Equatable { let id: String /* bcp47 */; let name: String }`
  - `static func LivePreviewLanguages.sortedOptions(_ identifiers: [String], displayLocale: Locale) -> [LanguageOption]`: sorts by localized name.

- [ ] **Step 1: Write the failing test** (append to `LiveTranscriberTests`)

```swift
    func testLanguageOptionsAreNamedAndSorted() {
        let options = LivePreviewLanguages.sortedOptions(
            ["te-IN", "en-US", "en-IN"], displayLocale: Locale(identifier: "en-US"))
        XCTAssertEqual(options.map(\.id), ["en-IN", "en-US", "te-IN"])
        XCTAssertEqual(options.first?.name, "English (India)")
    }
```

- [ ] **Step 2: Run it to make sure it fails** (Test command, `-only-testing:RayeeTests/LiveTranscriberTests`). Expected: "type 'LivePreviewLanguages' has no member 'sortedOptions'" (or the type is missing).

- [ ] **Step 3: Implement**
  - **`SettingsManager`:** add the two keys and properties in the existing `didSet` style. Load them in `init`, defaulting to `true` when the key is absent, like `autoPasteEnabled`. Reset both in `resetToDefaults`.
  - **`LivePreviewLanguages`** (then run `python3 -I scripts/xcodeproj_files.py add LivePreviewLanguages.swift`):
    - **`load()`:** read `SpeechTranscriber.isAvailable` and `SpeechTranscriber.supportedLocales`, then build `options` with `sortedOptions(..., displayLocale: .current)`. Names come from `displayLocale.localizedString(forIdentifier:)`. Publish on the main thread.
    - **`choose(_:)`:**
      1. Release every locale in `AssetInventory.reservedLocales` other than the chosen one, using `AssetInventory.release(reservedLocale:)`.
      2. Reserve the chosen one with `AssetInventory.reserve(locale:)`.
      3. If `AssetInventory.assetInstallationRequest(supporting: [SpeechTranscriber(locale:preset:)])` returns a request, observe `request.progress.fractionCompleted` into `downloadProgress`, `await request.downloadAndInstall()`, then set `downloadProgress = nil`.
      4. Log any error under category `"live"`, and never show an alert.
  - **`RecordingSettingsTab`:** add a new `Section` **above** "Stop after silence":
    - `Toggle("Show words while I speak", isOn: $settings.livePreviewEnabled)`.
    - When the toggle is on, a `Picker("Preview language", selection: $settings.livePreviewLanguage)` over `languages.options`. Next to it, while `downloadProgress != nil`, a small `ProgressView`: determinate when the value is > 0, otherwise indeterminate, with the label "Downloading…".
    - On selection change, call `Task { await languages.choose(newValue) }`.
    - On appear, call `load()` and then `choose(settings.livePreviewLanguage)`, so the default language is reserved and downloaded once.
    - Footer, exact copy:
      - Normally: "See your words in the recorder as you speak. The pasted text still comes from your speech model."
      - If `!isAvailable`, or the chosen id isn't in `options` (once `options` has loaded): "This Mac can't show live words for this language. Dictation works as usual."

- [ ] **Step 4: Run the tests.** Run the Test command with no filter. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add swift/Rayee/Rayee/SettingsManager.swift swift/Rayee/Rayee/LivePreviewLanguages.swift swift/Rayee/Rayee/RecordingSettingsTab.swift swift/Rayee/RayeeTests/LiveTranscriberTests.swift swift/Rayee/Rayee.xcodeproj/project.pbxproj
git commit -m "feat: live preview switch and language in Settings"
```

---

### Task 4: Wire it into recording and the recorder

**Files:**
- Modify: `swift/Rayee/Rayee/TranscriptionCoordinator.swift:72-85, 124-132, 151-220`
- Modify: `swift/Rayee/Rayee/AppState.swift:180-184`
- Modify: `swift/Rayee/Rayee/RecorderController.swift:31-107, 193-200`
- Modify: `swift/Rayee/Rayee/RecorderView.swift:16, 82-94`

**Interfaces:**
- Consumes: `LiveTranscriber` + `AudioRecorder.onRawBuffer` (Task 2), `SettingsManager.livePreviewEnabled/livePreviewLanguage` (Task 3), `LiveTranscript`, `RecorderLayout.bodyHeight(for:liveLines:)`, `RecorderLayout.liveLines(previous:transcript:)`, `RecorderRules.acceptsLiveTranscript(in:)` (Task 1).
- Produces:
  - `TranscriptionCoordinator.onLiveTranscript: ((LiveTranscript) -> Void)?`
  - `RecorderController.showLiveTranscript(_ transcript: LiveTranscript)`
  - `RecorderController.liveTranscript: LiveTranscript` (`@Published private(set)`)
  - `RecorderController.bodyHeight: CGFloat` (computed)

- [ ] **Step 1: Coordinator**
  - Add `private var liveTranscriber: LiveTranscriber?` and `var onLiveTranscript: ((LiveTranscript) -> Void)?`.
  - In `beginRecordingSession`, after the `audioRecorder` is created and before `startRecording()`, if `settings.livePreviewEnabled`:
    - Create `LiveTranscriber(languageIdentifier: settings.livePreviewLanguage)` and store it.
    - Set `audioRecorder?.onRawBuffer = { [weak transcriber] in transcriber?.append($0) }`.
    - Set `transcriber.onTranscript = { [weak self, weak transcriber] t in guard let self, let transcriber, self.liveTranscriber === transcriber else { return }; self.onLiveTranscript?(t) }`.
    - Call `transcriber.start()`.
  - Add `private func stopLiveTranscriber()`, which calls `liveTranscriber?.stop()` and then sets `liveTranscriber = nil`. Call it first thing in `handleRecordingComplete`, in `handleRecordingError`, and inside `cancel()`'s `if isRecording` block. That covers hotkey stop, click stop, silence auto-stop, the max-duration stop, start failure, and Esc.

- [ ] **Step 2: Recorder**
  - In `RecorderController`, add `@Published private(set) var liveTranscript = LiveTranscript()` and `private var liveLines = 0`.
  - Add `var bodyHeight: CGFloat { RecorderLayout.bodyHeight(for: phase, liveLines: liveLines) }`, and use it in `pointerMoved()` in place of `RecorderLayout.bodyHeight(for: phase)`, so the hit area matches the shape.
  - **`showLiveTranscript(_:)`:**
    - Return unless `RecorderRules.acceptsLiveTranscript(in: phase)`.
    - Compute `RecorderLayout.liveLines(previous: liveLines, transcript:)`.
    - If the line count grew, set `liveTranscript` and `liveLines` inside `withAnimation(RecorderMotion.change)`; otherwise set `liveTranscript` without animation. That way the body moves only when a line is added, not on every update.
  - **In `show(_:)` and `hide()`:** reset `liveTranscript = LiveTranscript()` and `liveLines = 0` whenever the phase changes, inside the same `withAnimation` as the phase change. Text never carries over into Transcribing or into the next recording.
  - In `RecorderView`, change `bodyHeight` (line 16) to `controller.bodyHeight`. Wrap the `listening` view in a `VStack(spacing: 0)`:
    - The existing `HStack` comes first, unchanged, framed to `height: RecorderLayout.compactHeight`.
    - Then, when `!controller.liveTranscript.isEmpty`, a `Text` built from `controller.liveTranscript.visibleTail(maxCharacters: RecorderLayout.charsPerLine * RecorderLayout.maxLiveLines)`:
      - `Text(tail.settled).foregroundStyle(.white.opacity(0.9)) + Text(tail.draft).foregroundStyle(.white.opacity(0.45))`
      - `.font(.system(size: 13))`, `.lineLimit(RecorderLayout.maxLiveLines)`, `.frame(maxWidth: .infinity, alignment: .bottomLeading)`
      - `.padding(.horizontal, 18)`, `.padding(.bottom, 12)`, `.allowsHitTesting(false)`
    - Keep the `VStack` top-aligned, so the dot, bars and timer don't move when text appears.
- [ ] **Step 3: AppState.** Next to `onAudioLevelUpdate` (`AppState.swift:181-184`), add `transcriptionCoordinator.onLiveTranscript = { [weak self] t in self?.recorder.showLiveTranscript(t) }`.

- [ ] **Step 4: Build and test.** Run the Build command, then the Test command.
Expected: `BUILD SUCCEEDED`, then `** TEST SUCCEEDED **`, with every existing test still passing.

- [ ] **Step 5: Commit**

```bash
git add swift/Rayee/Rayee/TranscriptionCoordinator.swift swift/Rayee/Rayee/AppState.swift swift/Rayee/Rayee/RecorderController.swift swift/Rayee/Rayee/RecorderView.swift
git commit -m "feat: show live words in the notch recorder while dictating"
```

---

### Task 5: Measure on the user's Mac (hard stop)

Run this in the main session with the user, not in a subagent. **Building pauses until the numbers are in.**

- [ ] **Step 1: Launch.** Run the Build command, then `open swift/Rayee/build/Build/Products/Debug/Rayee.app`. Confirm that Settings → Recording shows the switch on, with "English (India)" chosen.
- [ ] **Step 2: Preview off baseline.** Ask the user to turn the switch off and do one ~1-minute English dictation into TextEdit. While it runs, record Rayee's memory and CPU with `top -l 8 -s 5 -pid $(pgrep -x Rayee) -stats pid,mem,cpu > swift/Rayee/build/live-off.txt`. Note the time from the hotkey press to "Pasted" from the app log.
- [ ] **Step 3: Preview on.** Same dictation with the switch on, saving to `swift/Rayee/build/live-on.txt`. Read `"Live first words after"` from the app log (`AppLogger` file). If the log says `"needs speech-recognition permission"`, **stop and tell the user**. Asking for that permission would change onboarding, so it's their decision.
- [ ] **Step 4: Thresholds (from the spec).** Stop and bring the numbers to the user, without polishing further, if any of these happens:
  - Memory with the preview on exceeds memory with it off by more than **~50 MB**.
  - First words take longer than **~2 s**.
  - The pasted text or its timing differs from the preview-off run.
- [ ] **Step 5: Quick checks** with the user in the same sitting:
  - Esc in the first second.
  - Two recordings back to back, where the second must not show the first one's words.
  - The switch off: the recorder looks exactly as it did before this feature.
- [ ] **Step 6: Record and commit.** Write the numbers and the check results into the Session log of `docs/plans/2026-10-15-00-improvement-roadmap.md`, then commit with `docs: live transcription measurements`.

---

### Task 6: Clean up, docs, final review

**Files:**
- Modify: `swift/Rayee/Rayee/LiveTranscriber.swift` (remove the temporary first-words log)
- Modify: `ROADMAP.md`, `README.md` (Features list)
- Modify: `docs/plans/2026-10-15-00-improvement-roadmap.md` (Status table, "Hands-on checks carried forward", Session log)

- [ ] **Step 1: Remove the measurement log.** Delete the temporary `"Live first words after"` log from Task 2. Keep the error logs.
- [ ] **Step 2: Update the docs.**
  - `README.md`: add "**Live Preview** - See your words in the recorder as you speak (English, Telugu and more, via macOS)" under Features.
  - `ROADMAP.md`: move Live Transcription from "Future" to a "Completed" section, describing what was actually built.
  - Roadmap file: mark Phase 4 as Done. Add the spec's seven "Testing by hand" checks, word for word, to "Hands-on checks carried forward".
- [ ] **Step 3: Full test run.** Run the Test command. Expected: `** TEST SUCCEEDED **`.
- [ ] **Step 4: Commit** with `docs: live transcription shipped; hands-on checks carried forward`.
- [ ] **Step 5: Final review.** Run one whole-branch review (superpowers:requesting-code-review) against `main`. Fix any Critical or Important findings, re-run the tests, commit, then use superpowers:finishing-a-development-branch.
