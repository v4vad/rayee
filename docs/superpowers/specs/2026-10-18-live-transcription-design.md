# Live transcription: design (2026-10-18)

Phase 4 of `docs/plans/2026-10-15-00-improvement-roadmap.md`. The engine research and the
measurements from the user's Mac are in `docs/brainstorms/2026-10-17-live-transcription-engines.md`.
This document builds on that research and does not repeat it.

Branch: `feature/live-transcription` (made from `main` after the design refresh merged).

## Intent

While the user dictates, Rayee shows their words in the notch recorder as they speak. The user
mostly dictates in English and sometimes in Telugu.

Why the user wants it (from the brainstorm):
- **Pausing to think.** When they stop to think partway through, they can glance up, see their
  last sentence, and carry on from there.
- **Knowing it's hearing them.** Within about a second they can see the mic works and the
  language is right, instead of finding out after a long dictation captured nothing.
- **Long dictations.** It's easier to keep their place.

What it does **not** do: the result doesn't arrive any sooner, and the pasted text doesn't
change. Live text is a preview of what's coming. The pasted text still comes from Whisper.

## Goals

1. Words show up in the notch recorder about a second after they're spoken (the spike measured 1.07–1.08 s).
2. Draft words look different from settled words, so the user can tell which ones may still change.
3. The pasted text, Smart Dictation, the Vocabulary list and History behave exactly as they do today.
4. Rayee's memory doesn't grow noticeably. Apple's recognizer runs in a separate macOS process.
5. English works with no download. Telugu works after a one-time macOS download.

## Non-goals

- Typing words into the target app while the user speaks. Nothing is typed until they stop.
- Making the final result arrive faster.
- Ending a recording when the user pauses. **The user stops with the hotkey.** Pauses must never end
  a recording early. The existing silence auto-stop (default 30 s, Settings → Recording) stays as a
  safety net only, and roadmap item F3 ("stop at a natural pause") stays undone.
- Using Apple's text as the pasted result, for any language (see Telugu below).
- Showing what Smart Dictation's cleaned-up version will look like while the user speaks.
- Replacing Whisper, or changing which Whisper model is used.

## Anti-goals (failure even if it technically works)

- **A pause cuts the user off,** or makes the recorder behave as though they finished.
- **Rayee crashes because of live text.** Apple's recognizer crashes the process when it's given
  Float32 audio (measured). Audio must always be converted to `SpeechAnalyzer.bestAvailableAudioFormat`
  (16 kHz mono Int16 on the user's Mac).
- **The pasted text gets worse or slower,** or Smart Dictation, Vocabulary or History change.
- **A live-text problem breaks dictation.** If Apple's recognizer fails to start, isn't
  available, or doesn't support the language, recording, transcription and paste must still
  work as they do today. The preview just doesn't appear.
- **The recorder jumps around.** Text arriving roughly once a second must not make the notch
  shape jitter or resize on every update.

## Constraints

- Pure native Swift, no new packages. Apple's `SpeechAnalyzer` / `SpeechTranscriber` (Speech
  framework, macOS 26) is the engine. This choice comes from the research and the user agreed to it.
- Minimum macOS 26.0. The user's Mac runs macOS 27. Apple's language list on macOS 26 may be
  shorter, so the code must ask macOS which languages it supports instead of hard-coding a list.
- Live text uses the audio Rayee already records (16 kHz mono Float32 from `AudioRecorder`). It
  must not open the microphone a second time.
- One writer per file during the build, and tests in `swift/Rayee/RayeeTests/` (synced
  automatically). App source files are added to `project.pbxproj` with
  `python3 -I scripts/xcodeproj_files.py add …`.
- Settings go through `SettingsManager` (UserDefaults).
- An app can reserve at most 5 languages with `AssetInventory` (`maximumReservedLocales`).

## Decided

**By the user:**
- Build live transcription with Apple's recognizer for the preview, and keep WhisperKit for the
  pasted text.
- The user stops a recording with the hotkey. Pauses keep recording.
- **Telugu, option 1:** the preview shows Telugu in English letters (that's what Apple returns), and the
  pasted text stays as Whisper's Telugu script. Revisit once the user has tried it with real Telugu speech.
- Performance gets measured on the user's Mac before the feature ships (see "First milestone").

**My calls, shown to the user and not objected to (they replied "ok"):**
- **Where:** inside the notch recorder (the floating capsule on screens without a notch), in the
  `listening` state. The recorder grows downward as text arrives and shows **the last 2–3 lines**.
  Older text scrolls off the top.
- **Look:** draft words are pale grey, and settled words are solid (the recorder's normal text
  colour). In practice, Apple only settles words after a pause or at the end, so most of a
  sentence spoken without a pause stays grey until the user pauses. That's expected.
- **On stop:** the live text goes away and the recorder moves on to "Transcribing", then "Pasted"
  (or "Cleaning up" first when Smart Dictation is on), exactly as today. The live text is thrown
  away and never saved.
- **Smart Dictation:** unchanged. The preview shows the raw words.
- **Setting:** a switch called "Show words while I speak" in Settings → Recording, **on by default**.
- **Unsupported language:** the preview is skipped silently and the recorder looks as it does
  today. A note in Settings says why when the chosen language isn't supported.

**My calls, settled after the builder check (user can override):**
- **Audio fed to the preview:** every buffer from the start of recording, silence included,
  tapped *before* any speech gating or pre-roll in `AudioRecorder`. Pauses then line up with
  real time, and the speech detection and auto-stop logic stay exactly as they are.
- **Silence auto-stop** ends the preview the same way a hotkey stop does. **Cancel / Esc while
  listening** throws the preview away. In every case the recognizer is torn down **without
  waiting** for it. Nothing in the stop, paste or cancel path ever waits on the preview.
- **Recorder layout:** at most **3 lines** of live text. The width stays as it is today. The
  notch shape and the floating capsule behave the same way. It grows one line at a time
  through the existing body-height path (`RecorderLayout.bodyHeight`) and never shrinks while
  recording. The text can't be clicked, so it never gets in the way of the recorder's existing
  click and Esc behaviour.
- **Language downloads:** progress shows in Settings only. If the chosen language isn't
  installed when a recording starts, the preview is skipped silently (and the download
  continues). Rayee reserves only the chosen language and releases the previous one when the
  user switches, so it stays well under the 5-language limit.
- **Measurement:** a hard stop after the first working build. The builder adds a temporary
  debug log line for the time to first words. The main session then asks the user for one
  1-minute dictation and reads Rayee's memory and CPU use while it runs. Building pauses until
  the numbers are in.

## Left to decide (my proposal, user to confirm)

- **Which language the preview listens for.** Apple's recognizer needs one language per
  recording. Whisper guesses the language by itself each time, and Rayee has no language
  setting today. My proposal: a "Preview language" menu under the switch, defaulting to
  **English (India)**. It lists only the languages macOS reports as supported (Telugu included on
  macOS 27). Picking a language that isn't installed starts the macOS download, with progress
  shown next to the menu. Whisper keeps guessing by itself, unchanged.

## Left to the builder

- How to structure the code. A new `LiveTranscriber` type wrapping `SpeechAnalyzer` is the
  research's suggestion. Likely touch points: `AudioRecorder.swift` (pass converted buffers on),
  `TranscriptionCoordinator.swift` / `RecorderController.swift` (start and stop alongside
  recording), `RecorderState.swift` / `RecorderView.swift` (show the text, size the body),
  `SettingsManager.swift` and `RecordingSettingsTab.swift` (switch and language).
- How to keep the recorder from jittering. For example, grow the body one line at a time,
  with a short animation, and never shrink while recording.
- The exact grey for draft words, as long as it's readable on the notch's black background.
- Which preset to use. The spike used `timeIndexedProgressiveTranscription`.
- How to start Apple's recognizer early enough that the first words aren't late. Preparing it
  when recording starts took a measurable time in the spike (`prepareToAnalyze`).
- Unit tests for the testable parts: buffer conversion to Int16, the logic that splits text
  into draft and settled parts, and body height for live text. The recognizer itself can't run
  in unit tests.
- How live text is held: inside `RecorderPhase.listening` or beside it. Existing tests that
  compare phases must keep passing either way.

## First milestone: measure before polishing

The first working build must be measured on the user's Mac, in the real app, and the numbers
written into the plan's session notes before any polishing:
- time from pressing the hotkey to the first live words
- Rayee's memory with the preview on vs off
- CPU use during a 1-minute dictation
- that the pasted text and its timing match the preview being off

If Rayee's memory grows by more than about 50 MB, or the first words take longer than about 2 s,
stop and bring the numbers to the user before continuing. These thresholds are my call.

## Testing by hand (add to the roadmap's "Hands-on checks carried forward")

The user tests at release time. Add these to that list:
- English dictation: grey words appear within about a second and turn solid after a pause.
- Pause for 10 s mid-sentence: the recording keeps going, and new words follow on.
- A long dictation (1 minute or more): only the last 2–3 lines show, and the recorder doesn't jitter.
- Smart Dictation on: the preview shows raw words, and "Cleaning up" and the paste work as before.
- Switch off: the recorder looks exactly as it did before this feature.
- Telugu as the preview language: the first-time download shows progress, the preview is in English
  letters, and the paste is in Telugu script.
- Microphone denied or recognizer unavailable: dictation still behaves as today.
