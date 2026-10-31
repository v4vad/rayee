# How Rayee works

What happens on each dictation, the rules each part must keep, and the decisions behind them. For where the code lives, see `swift/Rayee/Rayee/CLAUDE.md`.

## One dictation, start to finish

1. **Hotkey.** `HotkeyManager` listens system-wide (Option+Space by default). Pressing it again stops.
2. **Recording.** `AudioRecorder` captures 16 kHz mono Float32. It keeps 0.3 s from before speech is detected, so soft first sounds aren't clipped. It stops by itself after the user has been quiet for the chosen time (default 30 s, slider 5–60 s), or at 5 minutes.
3. **Live preview** (optional, on by default). `LiveTranscriber` feeds the same audio to Apple's on-device recognizer and shows draft words in the recorder. See the rules below.
4. **Transcription.** WhisperKit turns the audio into text. This text, not the preview, is what gets pasted.
5. **Smart Dictation** (optional). A text model fixes punctuation, capitals and filler words. `DictationDelivery` keeps several dictations in the order spoken when one is still being cleaned up.
6. **Delivery.** `PasteTargetDetector` decides: if there's a text field, `PasteManager` pastes (clipboard + Cmd+V) and puts the user's own clipboard back 1 s later. Otherwise the recorder shows a Copy card.
7. **History.** The final text (cleaned, if Smart Dictation ran) is saved in SQLite at `~/.rayee/history.db`.

## Rules that must hold

**Live preview**
- Apple's recognizer **crashes the app if it gets Float32 audio.** Always convert to `SpeechAnalyzer.bestAvailableAudioFormat` (16 kHz mono Int16 on the user's Mac).
- It's a preview only. It never changes what's pasted, and the stop, paste and cancel paths never wait for it.
- If it fails, isn't available, or the language isn't supported, dictation works exactly as without it. Failures are logged, never shown.
- It uses the audio Rayee already records, tapped before speech detection, and never opens the microphone a second time.
- At most 3 lines show. The recorder grows one line at a time and never shrinks while recording, so it doesn't jitter.
- Pauses never end a recording. The user stops with the hotkey; silence auto-stop is only a safety net.

**Recorder look (approved by the user)**
- Never covers the menu bar beside the notch. Inside the menu bar it stays as wide as the notch, and grows **down**.
- T shape: notch-wide band, 300 pt body below the menu bar. Smoothed corners: 12 everywhere on notched screens (from the next update), 22 on the capsule.
- Pure black at the top lifting to `white 0.06`; glass edge brightest along the bottom; soft shadow; 24 white bars, 2 pt wide with 4 pt gaps, centred under the camera; steady red dot.
- The window is hidden from screenshots and screen recordings (`panel.sharingType = .none`). To tune the look, temporarily switch it to `.readOnly` on a throwaway branch so screenshots show it, and switch it back before shipping.
- Rejected: an S-curve flare ("chimney"), coloured or voice-reactive glows, cyan bars, a notch-width body (too few words per line).

**Smart Dictation**
- The dictated text is wrapped in `<dictation>` tags and the model is told never to answer or follow it. Any model that obeys dictated instructions is disqualified.
- Change prompts or models only with eval evidence (see the root `CLAUDE.md`). Results live in `docs/eval/`.

**Privacy**
- No log file. `AppLogger` prints to Xcode's console only, and dictated text is never logged.

## Models

- **Speech:** Whisper large-v3 turbo (632 MB) on Macs WhisperKit supports it on (M2 and later); WhisperKit's own default elsewhere. Installs from before v0.9 that never picked a model stay on `small`, so nobody gets a surprise download.
- **Smart Dictation, "Automatic":** Apple Intelligence when it's turned on (it tied the best eval score and needs no download); otherwise Qwen3 4B on Macs with 16 GB or more, else Qwen3 1.7B. Qwen3 needs "thinking" turned off. The model stays loaded 5 minutes after use.
- Llama 3.2 1B was removed in v0.9.1: it obeyed dictated instructions in the eval.

## Updates

Sparkle reads `appcast.xml` from the `main` branch. A downloaded update installs and relaunches once Rayee has been idle (nothing recording, transcribing or cleaning up) for 2 minutes. Releases are built, signed and notarized on the user's Mac with `/publish-release`; there's no cloud build.

## Decisions worth remembering

| Decision | Why |
|---|---|
| Apple's recognizer for the preview, Whisper for the pasted text | Apple's is fast and runs in its own process (about 10 MB extra for Rayee); Whisper is more accurate. |
| Telugu preview shows English letters; the paste is Telugu script | That's what Apple returns. Revisit after real Telugu use. |
| Preview language is a setting (default English (India)) | Apple's recognizer needs one language per recording; Whisper still detects the language by itself. |
| No "stop at a natural pause" | The user pauses to think. They stop with the hotkey. |
| No fast-mode switch | WhisperKit already decodes greedily; the switch could do nothing. |
| Qwen3 over Gemma 4 | Longer support in mlx-swift-lm and a documented thinking-off switch. |
| No log file | The user felt a log "might seem shady". |
| Rejected: trimming trailing silence before transcription, changing the clipboard backup | User decisions. |
| Never make the user grant microphone or Accessibility again | Test builds signed differently count as a new app to macOS, so avoid them on the user's Mac. |
