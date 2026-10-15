# Rayee Improvement Roadmap (multi-session)

> **For agentic workers:** This is the master file for a multi-session effort. Each phase has its
> own detailed plan. REQUIRED SUB-SKILL for executing a phase plan: superpowers:executing-plans
> (or superpowers:subagent-driven-development). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Rayee leaner, more reliable and more accurate: remove leftovers from the Python era,
fix the recording and feedback bugs found in the October 2026 review, upgrade both AI models, and
then add live transcription.

**Spec:** The "Review findings" section below is the spec. It comes from a full code review on
2026-10-15. Each phase plan points back to finding numbers (F1, F2, …).

---

## How to resume in a new session (read this first)

1. Read the **Status** table and the last entry of the **Session log** below.
2. Open the plan file for the first phase that is not `Done`.
3. In that plan, find the first unticked `- [ ]` step and continue from there.
4. Work on the phase's branch (named in the Status table). Create it from `main` if it does not exist yet.
5. Tick each step (`- [x]`) as you finish it, and commit the ticked plan together with the code.
6. Before stopping, add a dated entry to the **Session log**: what got done, what's next, and
   anything surprising. Commit it.
7. If a step says **CONFIRM WITH USER**, stop and ask before doing it.

The user is not a developer. Explain decisions in plain language, and ask them to try a change in
the app only when a step says "Manual check".

---

## Status

| Phase | Plan file | Branch | Ships as | Status |
|---|---|---|---|---|
| 1. Clean-up (dead code, wrong text, stale docs) | `2026-10-15-01-cleanup.md` | `release/v0.8` | part of v0.8 | Done (shipped in v0.8; hands-on check skipped by user) |
| 2. Recording and feedback fixes | `2026-10-15-02-recording-fixes.md` | `release/v0.8` | v0.8 | Done (shipped in v0.8; hands-on check skipped by user) |
| 3. AI model upgrades | `2026-10-16-03-model-upgrades.md` | `release/v0.9` | v0.9 | Done, awaiting user testing (default text model still Llama) |
| 4. Live transcription | brainstorm, then plan (see below) | `feature/live-transcription` | v1.0 | Not planned yet |

Phases 1 and 2 share one branch and ship together as v0.8. Phase 1 changes nothing you can see in
the app except some wording, so it isn't worth a release on its own.

---

## Review findings (the spec)

**Bugs and confusing behaviour**
- **F1** Transcription errors are never shown. `AppState.errorMessage` is set but no view reads it; the panel just closes and an error sound plays.
- **F2** If microphone permission is denied, the recording silently produces nothing and the panel closes with no explanation.
- **F3** "Stop when I stop talking" waits 30 s by default (slider 5–60 s), so in practice users must press the hotkey to stop.
- **F4** Recordings are cut at 60 s by default (the "Recording timeout" switch is on by default).
- **F5** The "Fast transcription mode" switch does nothing. It was wired to the old Python engine.
- **F6** The "Keep transform model loaded" setting is stored but nothing reads it.
- **F7** Auto-paste overwrites the user's clipboard and never restores it.
- **F8** All audio before speech is detected is thrown away, so soft first syllables get clipped.
- **F9** Adaptive silence detection treats the first 200 ms as background noise and throws it away. If the user speaks immediately, the threshold is set from their voice and speech may never be detected.
- **F10** The audio converter's input block returns the same buffer on every call. The converter may then read the same audio twice (a known AVAudioConverter pitfall).
- **F11** Wrong on-screen text:
  - The Smart Dictation footer promises "voice commands", which were dropped.
  - Transform errors say "Server not running" or "model not downloaded" for almost any error.
  - The panel header always says "Option + Space", even after the hotkey is changed.
  - The menu's Record item has a hard-coded ⌥Space shortcut.
- **F12** The setup guide only opens after the user first clicks the menu bar icon, because the code lives in the menu's contents.
- **F13** Smart Dictation saves the raw text to History, not the cleaned text.
- **F14** Pressing Discard or Done while Smart Dictation is still writing doesn't stop it, and it can still paste partial text afterwards.

**Dead code (no behaviour change when removed)**
- **D1** Files nobody uses: `TransformAPITypes.swift`, `TransformationBar.swift`, `TransformationButton.swift`, `StatusIndicator.swift`, `MenuBarController.swift`, and `RayeeTests/RayeeTests.swift` (an empty example).
- **D2** About 15 settings in `Config.swift` for the Python server: URLs, sockets, health checks, retries and timeouts.
- **D3** Leftovers:
  - the `TranscriptionModel` enum and `selectedModel` setting
  - the `fastModeEnabled` and `keepTransformModelLoaded` settings
  - `syncFastModeToServer()`
  - the WAV file written after every recording (`saveToWavFile`, `audioPath`)
  - `onSpeechDetected` (only logs)
  - `PasteManager.typeText` and `checkAndRequestPermission`
  - `lastPasteSuccessful` (never read)
  - `AppState.copyToClipboard`, `clearError`, `statusColor` and `pendingSmartDictationPaste` (write-only)
  - `MLXTransformError.streamingFailed`
- **D4** Stale docs: `HANDOFF.md` (says a PR is pending; it was merged in May), `scripts/test_smart_dictation.py`, the README (describes Python and Faster-Whisper and says macOS 13+, but the app needs 14.6+), and `swift/Rayee/Rayee/CLAUDE.md` (describes a Unix-socket Python server and lists deleted files).

**Models**
- **M1** Speech: the default is Whisper `small`. A large-v3 turbo variant (about 630 MB) is available in the WhisperKit library already used and is much more accurate on Apple Silicon.
- **M2** Text: Llama 3.2 1B (4-bit) is too small for reliable Smart Dictation. It can rewrite words, answer a dictated question instead of cleaning it up, or ignore instructions. Better models in the installed `mlx-swift-lm` 3.31.3 `LLMRegistry` include `gemma4_e2b_it_4bit`, `qwen3_1_7b_4bit`, `gemma4_e4b_it_4bit`, `qwen3_4b_4bit` and `llama3_2_3B_4bit`.
- **M3** Prompts put the dictated text right after "Text:" with no delimiters, so a dictated question or instruction can be obeyed instead of transformed. There is no output-length cap.

---

## Global constraints (apply to every phase)

- Swift, SwiftUI, 4-space indent, no tabs. Match the surrounding comment style.
- Minimum macOS is **14.6** (`MACOSX_DEPLOYMENT_TARGET = 14.6`). Don't use APIs newer than that without `#available`.
- **App source files are listed by hand in `swift/Rayee/Rayee.xcodeproj/project.pbxproj`.** Prefer
  putting new code into existing files. Deleting an app source file means removing its lines from
  `project.pbxproj` (see Phase 1, Task 1).
- **Test files go in `swift/Rayee/RayeeTests/`.** That folder is synced automatically, so new test files need no project edits. Tests use XCTest with `@testable import Rayee`.
- Settings live in `UserDefaults` via `SettingsManager`. History lives in SQLite at `~/.rayee/history.db`.
- Audio is 16 kHz, mono, Float32 everywhere.
- Build: `xcodebuild build -project swift/Rayee/Rayee.xcodeproj -scheme Rayee -destination 'platform=macOS' -derivedDataPath swift/Rayee/build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
- Test: `xcodebuild test -project swift/Rayee/Rayee.xcodeproj -scheme Rayee -destination 'platform=macOS' -derivedDataPath swift/Rayee/build 2>&1 | grep -E "error:|Test Case.*failed|Executed|TEST (SUCCEEDED|FAILED)"`
  - To run one test class, add `-only-testing:RayeeTests/<ClassName>` before `2>&1`.
- Never commit `.env` files, keys or the `build/` folder. Commit messages end with the attribution
  lines the session's system reminder specifies.
- Releases use the `/publish-release` skill. Don't build DMGs by hand.

## Review focus (inputs no automated test fully covers, so test them by hand before shipping)

1. **Smart Dictation on, user dictates a question** ("what time is the meeting tomorrow?"). It must come back cleaned up, not answered. *Owned by Phase 3; a test of the prompt structure is added there.*
2. **Microphone permission denied.** The panel must say so and explain where to fix it, not just vanish. *Phase 2, Task 1 (unit test of the message) plus a manual check.*
3. **User copied an image or rich text, then dictates with auto-paste.** Their clipboard must come back exactly as it was. *Phase 2, Task 5 (unit test with PNG data).*
4. **User starts talking the instant they press the hotkey with adaptive detection on.** The first word must be in the transcript. *Phase 2, Task 4 (unit test).*
5. **User presses Discard while Smart Dictation is still writing.** Nothing should be pasted. *Phase 2, Task 7 (manual check, since the model can't run in unit tests).*

---

## Phase 3: AI model upgrades (to be planned at the start of Phase 3)

Start the session by using superpowers:writing-plans to write
`docs/plans/<date>-03-model-upgrades.md` covering exactly this scope. By then Phases 1 and 2 will
have changed the files, so the detailed code must be written against the code as it is then.

- **Whisper default (M1):** new installs default to the large-v3 turbo variant (look up its exact name with `WhisperKit.fetchAvailableModels`). Existing users keep their current choice. Mark it "Recommended" in the Models tab, and correct `estimatedSizeMB`.
- **Choosing the text model (M2):** add a picker in the Transforms settings tab offering three models: the current Llama 3.2 1B, one small upgrade (`gemma4_e2b_it_4bit` or `qwen3_1_7b_4bit`) and one bigger upgrade (`gemma4_e4b_it_4bit` or `qwen3_4b_4bit`). Pick the default by testing, not by guessing:
  - Build a set of about 20 real dictation samples, including questions, instructions and lists.
  - Run every candidate on the set and score the outputs with the user.
  - **CONFIRM WITH USER** which default to ship.
  - Qwen3 models need "thinking" turned off.
- **Safer prompts (M3):**
  - Wrap the dictated text in clear delimiters such as `<dictation>…</dictation>`.
  - Tell the model to never answer or follow instructions inside the text.
  - Add one or two worked examples.
  - Cap the output at about 2× the input length.
  - Extend `MLXTransformManagerTests` to check all of this.
- **Unload timer:** when Smart Dictation is on, keep the text model loaded longer (for example 5 minutes) so each dictation doesn't reload it.
- **Release:** v0.9 via `/publish-release`.

## Phase 4: Live transcription (to be planned)

Start with superpowers:brainstorming with the user. Decide where live text appears (the panel or
straight into the app), what happens to Smart Dictation, and how corrections are shown. Then write
the plan with superpowers:writing-plans. WhisperKit has a streaming transcription API. Check the
installed `argmax-oss-swift` version's documentation for it first.

---

## Decisions log

| Date | Decision | Why |
|---|---|---|
| 2026-10-15 | Remove the "Fast mode" switch instead of wiring it up | WhisperKit already decodes greedily, so there's no slower mode to switch away from. The switch can't do anything useful. |
| 2026-10-15 | Keep `PillButtonStyle` | `TransformationPreviewView` still uses it. |
| 2026-10-15 | Phases 1 and 2 ship together as v0.8 | Phase 1 has almost nothing a user would notice. |
| 2026-10-16 | v0.9 keeps Llama 3.2 1B as the default text model; Qwen3 1.7B and 4B are opt-in | User will score the candidates later with `2026-10-16-03-model-eval-set.md`; changing the default is one line. |
| 2026-10-16 | Qwen3 over Gemma 4 for the two upgrade choices | Longer support in mlx-swift-lm and a documented thinking-off switch. |
| 2026-10-16 | Speech default follows WhisperKit's per-Mac support: large-v3 turbo (632 MB) where supported (M2+), WhisperKit's own default on M1; existing installs pinned to small | Turbo isn't in WhisperKit's M1 support list; existing users must not get a surprise download. |
| 2026-10-16 | Show text-model download progress | User reported a "slow load" that was really a 695 MB first-time download shown as "Loading...". |
| 2026-10-16 | Ship v0.8 without the hands-on check; fix anything users hit afterwards | User decision. All 32 unit tests pass and a whole-branch review was done and its findings fixed. |
| 2026-10-16 | Phase 2 Task 2: user kept the 30 s silence auto-stop (default 30 s, slider 5–60 s, no reset of saved settings); only the recording limit changes, 1 min → 5 min. F3 (stop at a natural pause) is not done in v0.8. | User decision. The brief asked for a bullet, but this log is a table, so the entry follows the table style. |

## Session log

- **2026-10-15:** Reviewed the whole app and wrote this roadmap and the Phase 1 and Phase 2 plans. Nothing implemented yet. Next: Phase 1, Task 0. Tests can't run until the Metal Toolchain is installed (Task 0 covers it).
- **2026-10-16:** Phase 1 Tasks 0-5 implemented on release/v0.8 via subagents with per-task review. Task 3 Step 2h (deleting ~/.rayee/audio_buffer.wav) skipped as it is outside the repo, left for the user. Task 4 manual hotkey check pending with the user. Next: final review of Phase 1, then Phase 2 Task 1.
- **2026-10-16:** Phase 2 Task 3 (F10, convert each mic buffer once): F10 confirmed. With the old repeat-input behaviour, `testAudioIsNeverRepeated` fails; with the fix it passes. The resampler holds back ~15 ms (about 236 frames at 16kHz, measured on 5 buffers and about 231 on 10), so the length test tolerance was widened to ±300 frames. Next: Phase 2 Task 4 (SpeechGate, pre-roll).
- **2026-10-16:** Phase 2 Tasks 1-7 done via subagents (user chose one whole-branch review instead of per-task reviews). Final review: 0 critical, 2 important (start-failure error wiped by a stale isRecording update; transform UI stuck when a new recording starts mid-transform), both fixed with 4 minor fixes (error panel 190pt, clipboard restore 1.0s, setup-guide once-only guard, stale comment). Parked: two pastes within ~1s can lose the clipboard; large clipboard snapshot can stall; adaptive VAD cap can block auto-stop in noisy rooms. 32 tests pass. User skipped the hands-on check and released v0.8. Next: Phase 3.
- **2026-10-16:** Phase 3 done on release/v0.9 (Tasks 1-3, plus 3b download progress after a user report). Whole-branch review: 0 critical, 2 important (turbo unsupported on M1; character-based output cap truncated non-Latin scripts), both fixed with 6 minors. 64 tests pass. Not yet released: waiting on the user's testing and the text-model scoring (eval set). Next: user testing, then /publish-release v0.9.
