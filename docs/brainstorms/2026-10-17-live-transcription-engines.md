# Live transcription engines for Rayee — research (2026-10-17)

Research for **Phase 4: Live transcription** in `docs/plans/2026-10-15-00-improvement-roadmap.md`.
This file only compares engines. It does not decide where the live text shows up, what happens
to Smart Dictation, or how corrections look. Those decisions come later, in the Phase 4
brainstorm with the user.

**Constraints from CLAUDE.md:** pure native Swift, no Python, no server. Audio is 16 kHz mono
Float32. The app already requires macOS 26 (commit `fe2b58e`).

**Where the numbers come from:** model cards on Hugging Face, the libraries' GitHub READMEs and
release pages, Apple's developer documentation, and Argmax's own benchmark file. Where a number
comes from a vendor about its own product, or was measured on a Mac other than an M4 Pro, the
text says so. **No source publishes memory use for every engine on an M4 Pro.** Those figures
need measuring on the user's Mac before anything ships (see "Open questions").

---

## Short answer

| | Apple SpeechTranscriber | WhisperKit streaming (already in app) | NVIDIA Nemotron 3.5 Streaming | NVIDIA Parakeet v3 |
|---|---|---|---|---|
| **Built for live use?** | Yes ("progressive" mode) | Partly: it re-reads the recording about once a second | Yes, built for streaming from the start | **No.** It's a whole-file model; "live" means re-running it on overlapping windows |
| **Accuracy (published)** | 14.0% WER on earnings calls (Whisper small.en: 12.8%) ¹ | 2.17% WER live, large-v3 turbo ² | English 8.27% WER at 320 ms (FLEURS); 15-language average 9.49% ³ | Best of the four: 6.34% Open ASR average; English FLEURS 4.85% ⁴ |
| **Wait before words appear** | Not published. Apple says only "almost as soon as they're spoken" | ~0.94 s first guess, ~2.5 s until a word is final ² (M2 Ultra) | Chunk size you choose: 80 ms to 1.12 s (320 ms recommended) | 0.54 s first guess, 5.5 s until final ² (Argmax's **paid** SDK) |
| **Extra disk** | 0 inside the app. macOS downloads the model to system storage | 0 (the 632 MB turbo model is already there) | ~612 MB (Core ML int8 conversion) | ~480 MB (Core ML, FluidAudio) |
| **Extra memory** | Apple says it runs outside the app's memory | No new model, but the chip works continuously while recording | ~1.05 GB loaded, ~1.24 GB peak (measured on an **M5 Pro**) | Not published |
| **Languages** | About 10 at launch; **45 on macOS 27, incl. en-IN and Telugu** (measured) | ~99 (Whisper) | 19 good + 13 rough (40 language codes in all), **includes Hindi** | 25 European, **no Indian languages** |
| **Licence** | Free macOS feature | MIT | OpenMDW-1.1 (permissive, commercial use OK) | CC-BY-4.0 (commercial use OK if you credit NVIDIA) |
| **Pure-Swift route** | Built into macOS | Already in the app | Community ports only: speech-swift (Apache-2.0), or FluidAudio (English model only) | FluidAudio (Apache-2.0); live mode in Argmax Pro (paid) |
| **Custom vocabulary** | **No** ⁵ | Yes (Rayee's Vocabulary tab already uses it) | No | Only in Argmax Pro |

¹ Argmax's comparison, M4 Mac mini. ² Argmax OpenBench, M2 Ultra. ³ NVIDIA model card. ⁴ NVIDIA
model card. ⁵ OpenBench notes that Apple's docs say SpeechAnalyzer has no custom vocabulary.
Links are in the per-engine sections.

---

## 1. Apple SpeechAnalyzer / SpeechTranscriber (macOS 26)

**What it is:** Apple's new built-in speech recognizer, which replaces the old `SFSpeechRecognizer`.
`SpeechAnalyzer` runs the session and `SpeechTranscriber` turns speech into text.

- **Live mode:** the `progressiveTranscription` preset turns on `volatileResults` and `fastResults`.
  "Volatile" results are quick first guesses that keep changing. A result marked `isFinal` is
  settled, and Apple sends no more results for that stretch of audio. This is exactly the
  "grey words that firm up" pattern a live view needs.
  [Preset docs](https://developer.apple.com/documentation/speech/speechtranscriber/preset) ·
  [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)
- **Accuracy:** Apple publishes no WER. Third-party numbers:
  - Argmax, M4 Mac mini, earnings-call audio: SpeechTranscriber **14.0%**, WhisperKit base.en
    15.2%, small.en 12.8%, Parakeet v2 (paid SDK) 11.7%. That puts it between Whisper base and
    small, well below the large-v3 turbo Rayee uses now.
    [argmaxinc.com/blog/apple-and-argmax](https://www.argmaxinc.com/blog/apple-and-argmax)
  - OpenBench keyword test (earnings22): SpeechAnalyzer **17.0%** vs Parakeet v3 16.89%.
    [OpenBench BENCHMARKS.md](https://github.com/argmaxinc/OpenBench/blob/main/BENCHMARKS.md)
  - Both measured whole files, not live mode. Nobody has published a live-mode WER.
- **Delay:** not published. Apple only calls it low-latency.
- **Memory and disk:** Apple says the model "is retained in system storage and does not increase
  the download or storage size of your application, nor does it increase the run-time memory
  size". It runs outside the app's process. macOS downloads it on first use through
  `AssetInventory` (with a progress bar), and updates it automatically. The download size isn't published.
  [WWDC25 session 277](https://developer.apple.com/videos/play/wwdc2025/277/)
- **Languages:** check at runtime with `SpeechTranscriber.supportedLocales`. Apple's pages give
  no list. One third-party post lists the launch set as English, Spanish, French, German,
  Italian, Portuguese, Japanese, Korean, Chinese and Cantonese
  ([addpipe blog](https://blog.addpipe.com/apple-speechanalyzer-api/), not verified with Apple).
  Hindi and Telugu don't appear in that list. `DictationTranscriber` is the fallback for other
  languages: it is the older, less accurate model.
  [SpeechTranscriber docs](https://developer.apple.com/documentation/speech/speechtranscriber)
- **Licence:** part of macOS. No licence fee, no attribution.
- **How it would run in Rayee:** fully native, with nothing new to bundle. Rayee already requires
  macOS 26, so the minimum version is no obstacle. Audio buffers can be fed in directly, so it
  can share Rayee's existing recorder.
- **Catches:**
  - No custom vocabulary, so the user's Vocabulary list wouldn't affect live text.
  - Apps can only hold a limited number of language slots at a time.
  - Some developers report `isAvailable` returning false in the Simulator.
    ([Apple forums](https://developer.apple.com/forums/thread/802969))
  - It's a separate model from WhisperKit, so live text and final text could differ.

## 2. WhisperKit's own streaming (`AudioStreamTranscriber`)

**What it is:** a helper already inside the `argmax-oss-swift` package Rayee uses.

- **Installed version:** `Package.resolved` pins `argmax-oss-swift` to the `main` branch at
  commit `c9cf203` (1 May 2026; git calls it v0.17.0 plus 9 commits). The latest release is
  **v1.1.1 (8 Oct)**. It adds `inputDeviceID` to `AudioStreamTranscriber` and fixes recording
  not stopping when streaming hits an error (#533).
  [Releases](https://github.com/argmaxinc/argmax-oss-swift/releases)
- **How it works:** I read it in the checked-out source
  (`Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift`). It isn't true streaming. Once
  at least 1 second of new audio has built up (and a simple loudness check says someone is
  talking), it runs a full Whisper pass over the audio from the last confirmed point onwards. It
  then treats all but the last 2 segments as "confirmed" and the rest as "unconfirmed". So:
  - The chip works continuously while the user talks, and does more work per pass the longer
    they talk without a pause.
  - Text arrives in chunks about once a second, not word by word.
  - The helper starts its own microphone recording (`startStreamTranscription` asks for mic
    permission and records). Rayee would have to use its lower-level pieces with Rayee's own
    recorder, or the app would end up with two microphone pipelines.
- **Accuracy and delay (published):** Argmax OpenBench, live test on stitched TIMIT audio,
  M2 Ultra Mac Studio, large-v3 turbo through the Argmax local server: **2.17% WER, 0.94 s to the
  first guess, 2.51 s until confirmed.** Argmax says its default setup includes a 0.3 s sleep
  that can be removed. [OpenBench BENCHMARKS.md](https://github.com/argmaxinc/OpenBench/blob/main/BENCHMARKS.md).
  The WhisperKit paper (ICML 2025) gives 0.46 s latency and 2.2% WER.
  [arXiv 2507.10860](https://arxiv.org/abs/2507.10860)
  *Caveat:* Argmax measured this with its server setup on a much bigger chip than an M4 Pro, so
  expect it to be slower in Rayee.
- **Memory and disk:** no new download. It uses the large-v3 turbo model (632 MB) or small, as
  already loaded. The cost is that the chip and battery work continuously while recording.
- **Languages:** ~99, the same as today.
- **Licence:** MIT ([LICENSE](https://github.com/argmaxinc/argmax-oss-swift/blob/main/LICENSE)).
- **Plus:** it's the same model that writes the final text, so live and final text agree, and
  the Vocabulary prompt keeps working.

## 3. NVIDIA Nemotron 3.5 ASR Streaming 0.6B

**What it is:** NVIDIA's multilingual streaming model, released 4 June 2026. It has 600M
parameters, a cache-aware FastConformer-RNNT design, and built-in punctuation and capitals.
"Cache-aware" means it remembers what it already processed, so each new slice of audio costs
the same small amount however long the user talks. That's a real advantage over WhisperKit's
re-reading approach. [Model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)

- **Delay:** you choose the chunk size: 80, 160, 320, 560 ms or 1.12 s. The model emits text for
  each chunk, so the wait is about the chunk size plus compute time.
- **Accuracy (NVIDIA, FLEURS, language given rather than auto-detected):**

  | Chunk | 80 ms | 160 ms | 320 ms | 560 ms | 1.12 s |
  |---|---|---|---|---|---|
  | English WER | 9.43 | 8.88 | 8.27 | 7.99 | 7.91 |
  | Hindi WER | 8.13 | 7.97 | 7.41 | 7.05 | 6.81 |
  | Average, 15 main languages | 10.38 | 10.00 | 9.49 | 9.12 | 8.84 |
  | Average, 13 "broad coverage" languages | 25.86 | 25.14 | 24.11 | 23.09 | 22.13 |

  For comparison on the same test set, Parakeet v3 (whole-file) gets English 4.85%. The streaming
  model is noticeably less accurate than the best whole-file models.
- **Languages:** 19 "transcription-ready" language codes (incl. en-US/GB, Spanish, French,
  German, Italian, Portuguese, Dutch, Turkish, Russian, Arabic, **Hindi**, Japanese, Korean,
  Vietnamese, Ukrainian). There are also 13 "broad coverage" ones with ~20–30% WER, and 8 that
  need extra training first. No Telugu.
- **Licence:** OpenMDW-1.1 (permissive, commercial use allowed).
- **Official runtime:** NVIDIA NeMo (Python) or Transformers, on NVIDIA GPUs and Linux. **NVIDIA
  doesn't ship an Apple version.** Pure-Swift options are community ports only:
  - **speech-swift** by soniqo (Apache-2.0): module `NemotronStreamingASR`, with Core ML and MLX
    builds. Needs macOS 15+. Its GitHub page shows no tagged releases (only news posts, latest
    10 Sep 2026). [github.com/soniqo/speech-swift](https://github.com/soniqo/speech-swift) ·
    [guide](https://soniqo.audio/guides/nemotron)
  - Converted model `aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8`: **612 MB**, 320 ms
    chunks. On an **M5 Pro**: 18.6 ms per chunk (p50), RTF 0.068, **1,046 MB of memory after
    loading, 1,238 MB at peak**. Its WER is within about +0.3 points of NVIDIA's original for
    English. [Model card](https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8).
    MLX 5-bit is 539 MB on disk and peaks at 800 MB of memory (same guide).
  - **FluidAudio** (Apache-2.0) only supports the older **English-only** Nemotron Speech Streaming
    model (`NemotronStreamingAsrManager`). Its own measurements on an M2: 1.99% WER at 1.12 s and
    2.12% at 560 ms, but **~10% at 160 ms and ~60% at 80 ms**. NVIDIA's original scores 2.56% at
    160 ms, so FluidAudio's conversion breaks down at short chunks.
    [FluidAudio Nemotron Core ML](https://huggingface.co/FluidInference/nemotron-speech-streaming-en-0.6b-coreml) ·
    [NVIDIA English model](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b)
    FluidAudio's releases also say NVIDIA's Nemotron 3 models fail to compile for the M3 Neural
    Engine and fall back to slower paths (v0.17.2, v0.17.4).
    [FluidAudio releases](https://github.com/FluidInference/FluidAudio/releases)
- **Catches:**
  - It relies on a small, single-vendor community port with no tagged releases.
  - It adds ~600 MB to download and over 1 GB of memory, on top of WhisperKit and the text model.
  - It has no custom vocabulary.

## 4. NVIDIA Parakeet TDT 0.6B v3

**What it is:** NVIDIA's most accurate small model, also 600M parameters, released before
Nemotron 3.5. It's a **whole-file** model, not a streaming one. It has built-in punctuation and
timestamps. [Model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)

- **Accuracy (NVIDIA):** Open ASR Leaderboard average **6.34%** (LibriSpeech clean 1.93%). FLEURS:
  English 4.85%, Spanish 3.45%, German 5.04%; 25-language average 11.97%.
  FluidAudio's Core ML version on an **M4 Pro**: LibriSpeech clean 2.5%, FLEURS average 14.7%,
  ~156–210× faster than real time. [FluidAudio benchmarks](https://docs.fluidinference.com/reference/benchmarks)
- **Live use:**
  - Argmax measured Parakeet v3 live through its **paid Pro SDK**: 2.08% WER, 0.54 s to the first
    guess, but **5.51 s until confirmed**.
    [OpenBench](https://github.com/argmaxinc/OpenBench/blob/main/BENCHMARKS.md)
  - The free `argmax-oss-swift` has no Parakeet support at all.
  - The free FluidAudio README offers live mode through a `SlidingWindowAsrManager` (repeatedly
    re-running the model on overlapping ~15 s windows), but publishes no delay or WER for it.
    [FluidAudio](https://github.com/FluidInference/FluidAudio)
- **Languages:** 25 European languages, detected automatically. **No Hindi, Telugu or other Indian
  languages, and no Japanese or Chinese.**
- **Disk:** FluidAudio's Hugging Face repo holds many variants (3.6 GB in all), but the files
  the normal v3 path needs come to about **480 MB**: Preprocessor 0.5 MB, Encoder 445 MB, Decoder
  24 MB, JointDecision 13 MB. I added these up from the repo's file list
  ([files](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main)).
  Argmax's build is 494 MB. Memory use isn't published.
- **Licence:**
  - NVIDIA's model is CC-BY-4.0: commercial use is fine, but Rayee must credit NVIDIA, for
    example in the About box.
  - FluidAudio's SDK is Apache-2.0. Its model card shows both CC-BY-4.0 and Apache-2.0.
    CC-BY-4.0 is the one that applies.
- **Small streaming relative: Parakeet EOU 120M.** It's English only with no punctuation or
  capitals, and uses NVIDIA's Open Model License. NVIDIA reports 9.30% Open ASR average and
  80–160 ms delay.
  FluidAudio runs it (`StreamingEouAsrManager`) at 4.87% WER on LibriSpeech clean with 320 ms
  chunks (M2). It's useful mainly for its "you stopped talking" signal.
  [NVIDIA card](https://huggingface.co/nvidia/parakeet_realtime_eou_120m-v1) ·
  [FluidAudio streaming docs](https://docs.fluidinference.com/asr/streaming)

---

## What this means for Rayee

1. **Accuracy and liveness trade off.** The engines that feel truly live (Apple, Nemotron) are
   less accurate than the large-v3 turbo model Rayee already uses (Whisper small level for
   Apple; ~8% English WER for Nemotron). The very accurate options (Whisper turbo, Parakeet) are
   whole-file models with live mode bolted on, which costs chip time and delay.
2. **"Live preview, then a final pass" avoids the trade-off.** Show quick live text while the
   user speaks. When they stop, run today's WhisperKit transcription on the full recording, and
   paste or Smart-Dictate *that* text. The pasted result stays exactly as good as today, with
   the Vocabulary list, all of Whisper's languages, and Smart Dictation unchanged. The live text
   only has to be good enough to reassure the user.
3. **Languages matter for this user.** *(Corrected after measuring.)* On macOS 27, Apple handles
   Hindi and Telugu, the latter written in English letters. Whisper lists Telugu but its accuracy
   is unknown. Nemotron 3.5 has Hindi but no Telugu. Parakeet v3 drops all Indian languages.
4. **Memory adds up.** Rayee can already hold WhisperKit turbo (~632 MB) plus a text model
   (Llama 1B up to Qwen3 4B). Adding Nemotron or Parakeet means one more 0.5–1.2 GB model.
   Apple's model costs Rayee no memory.

## Measured on the user's Mac

Measured on 2026-10-17 on the user's M4 Pro running **macOS 27.0.1** (Swift 6.4). A throwaway
command-line tool lives in `.superpowers/spikes/live-transcription/`, which git ignores. The
test audio came from macOS's `say` command: an English sentence (Indian English voice "Rishi",
9.2 s) and a Telugu sentence (voice "Geeta (Enhanced)", 9.4 s), both saved as 16 kHz mono
Float32, the same format Rayee records. The tool pushed the audio to Apple's recognizer in
100 ms pieces, one every 100 ms, as if someone were speaking. It used the
`timeIndexedProgressiveTranscription` preset, which turns live "draft" results on. Because the
tool reads a file and never opens the microphone, it needed no permission prompts.

**This Mac runs macOS 27, not 26.** Apple's language list on macOS 26 may be shorter. Check it on
a macOS 26 Mac before relying on it there.

### 1. Languages

- **SpeechTranscriber (the new, better model) supports 45 language codes on macOS 27,** including
  **English (India) `en-IN`, English (US) `en-US`, and Telugu `te-IN`**. It also covers Hindi,
  Bengali, Gujarati, Kannada, Malayalam, Marathi, Tamil, Urdu, Punjabi, Odia, Nepali, Kashmiri,
  Maithili and a mixed Indian code `mul-IN`. That's far more than the 10 at launch that the
  earlier research found.
- Already installed: 9 English variants (including en-IN and en-US). Everything else downloads
  on first use.
- DictationTranscriber (the older fallback model) has 54 languages but **not Telugu**.
- An app can reserve at most **5 languages** at once (`AssetInventory.maximumReservedLocales`).
- Raw output is saved in `locales.txt` in the scratch folder.

### 2. Speed (time until words appear)

| Recording | First live words | Live updates | Final text | Wait after you stop talking |
|---|---|---|---|---|
| English, `en-IN` | **1.08 s** | about once a second, a few words at a time | 9.83 s | **0.19 s** |
| English, `en-US` | **1.07 s** | same | 9.76 s | **0.12 s** |
| Telugu, `te-IN` | **1.07 s** | same | 10.10 s | **0.25 s** |

- **Live text trails speech by roughly 1 second.** Each update covers the audio up to about
  0.1–0.3 s before it arrives. The draft text arrives in steps about once a second, not word by word.
- **The first "final" result only came at the end**, because neither test sentence had a long
  pause in it. In a 10 s sentence spoken without a pause, everything stays draft until you stop.
  After that, final text came back in 0.12–0.25 s, which is effectively instant.
- **English accuracy:** every word was right. The only problem was "three thirty" written as
  "**330**" instead of "3:30". The draft and final text matched apart from the closing full stop.
- **Telugu:** every word was recognised correctly, but **the text came back in English letters,
  not Telugu script**: "namaskaram nenu repu udayam padhi gantalaku Hyderabad office Ku vastanu
  dayachesi samaveshaniki avasaramaina patraalu siddham cheyandi". The draft text was a little
  rougher ("nenude", "pad") and the final text fixed it. I found no setting that switches the
  script.

### 3. Download, memory and chip use

- **English needed no download.** It was already on the Mac.
- **Telugu downloaded in 11.2 s** through `AssetInventory`. Apple's progress counter only reports
  "0 of 1 … 1 of 1", not bytes, so **the download size can't be seen from the app**. The files
  sit in macOS system storage, which this spike was not allowed to look at.
- **Memory:** the test tool itself peaked at about **20 MB**. The recognizer runs in a separate
  macOS process (`localspeechrecognition`). Midway through a run, that process used **13 MB plus
  about 156 MB held on the Neural Engine**, so roughly 170 MB in all, and none of it counts
  against Rayee. CPU use was almost nil (0.13 s of CPU time for a 10 s recording).

### 4. Can Rayee feed it the audio it already records?

**Yes, but Rayee has to convert the audio first.**

- `SpeechAnalyzer.start(inputSequence:)` with an `AsyncStream<AnalyzerInput>` of pushed buffers
  worked. So Rayee can pass on the buffers it already records, without opening the microphone a
  second time.
- **It only accepts 16 kHz or 8 kHz mono *Int16* audio**, which is what `bestAvailableAudioFormat`
  and `availableCompatibleAudioFormats` report. When the tool pushed Rayee's 16 kHz mono
  **Float32** buffers directly, the process **crashed** (exit code 133, no error message).
- Converting each buffer to 16 kHz Int16 with `AVAudioConverter` fixed it. Same sample rate,
  just a different number format, so this is cheap.
- Rayee must always convert to whatever `bestAvailableAudioFormat` says. Pushing Float32 crashes
  the app rather than returning an error.

### 5. Telugu in the other engines

- **Whisper (already in Rayee):** Telugu is in its language list (`"telugu": "te"` in
  WhisperKit's `Models.swift`). OpenAI publishes no Telugu accuracy figure, and its
  [model card](https://huggingface.co/openai/whisper-large-v3) warns of "lower accuracy on
  low-resource … languages". Rayee doesn't set a language today, so Whisper guesses it each time.
  It wasn't tested on Telugu in this spike.
- **Nemotron 3.5 Streaming: no Telugu.** It isn't in any of the 40 language codes on the
  [model card](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b). Nemotron is now
  out of the running for this user.
- **Parakeet v3:** no Telugu (25 European languages only).

## Recommendation (plain language)

*Updated after the measurements above.* Telugu makes the case for Apple stronger. On macOS 27,
Apple's recognizer is now the only live option that handles Telugu at all. Nemotron and Parakeet
don't, and Whisper's live mode is clumsy and untested for Telugu.

**Use Apple's built-in recognizer (SpeechTranscriber) to show words while you speak, and keep
WhisperKit for the final text that gets pasted.**

For Telugu there is one thing to decide in the Phase 4 brainstorm. Apple writes Telugu in
English letters, so the live preview would look different from Whisper's final text, which
writes Telugu script (accuracy untested). Should Telugu use Apple's text as the final result too,
or keep Whisper's? That's worth trying with real Telugu speech before deciding.

Why:
- **It costs Rayee nothing to carry.** macOS stores and runs the model itself, so Rayee gets no
  bigger and uses no extra memory. That matters, because Rayee already holds a speech model and
  a text model.
- **It's built for this.** It gives quick "draft" words that firm up as you keep talking, which
  is the behaviour a live view needs.
- **No new outside code to depend on.** It's part of macOS 26, which Rayee already requires.
- **Nothing gets worse.** The text that actually gets pasted still comes from today's WhisperKit
  model, with your Vocabulary list and Smart Dictation working as they do now.

The catch: some languages may not be covered. Live text would be skipped for those, and Rayee
would work as it does today. On macOS 27 the list is long (45 language codes, including English
India/US, Hindi and Telugu). On macOS 26 it may be shorter.

**Second choice:** WhisperKit's own streaming. It needs no new model and covers every language,
but it keeps the chip busy the whole time and text appears in roughly one-second jumps.
Updating `argmax-oss-swift` to v1.1.1 first would bring in a streaming bug fix.

**Not now:**
- **Nemotron 3.5** is the most impressive true streaming model and covers Hindi. But in Swift it
  only runs through a small community project, and it would add about 600 MB to download and
  over 1 GB of memory.
- **Parakeet v3** is the most accurate, but it isn't a live model, its live mode is mostly in a
  paid SDK, and it drops Indian languages. It's worth looking at later as a faster replacement
  for the *final* pass, not for live text.

## Open questions to settle before planning

- ~~Apple's delay, language list, and feeding it Rayee's buffers~~: answered in "Measured on
  the user's Mac".
- Still open: how much memory WhisperKit streaming uses on the M4 Pro (not measured).
- Still open: Apple's language list on macOS 26 (only macOS 27 was measured).
- Still open: Whisper's real accuracy on Telugu speech, and whether Telugu users prefer Telugu
  script or English letters.
- The text-model eval rules in CLAUDE.md cover prompts and text models. If the final pass ever
  moves off WhisperKit, the speech model needs an eval of its own first.

## Next session: what to do

1. **Wait until `feature/design-refresh` is merged into `main`.** Then start Phase 4 on a new branch made from `main`.
2. **Settle these with the user first** (superpowers:brainstorming), using this file as the brief:
   - Where live text appears: the notch panel, or typed straight into the app.
   - What happens to Smart Dictation.
   - How draft words and corrections look.
   - Telugu: keep Whisper's Telugu-script final text, or use Apple's English-letter text? Try both with real Telugu speech first.
   - What to do for languages Apple doesn't support: skip the live preview.
3. **Build a prototype:** a new `LiveTranscriber` wrapper around Apple's `SpeechAnalyzer`. Rayee's existing recorder feeds it buffers, converted to `bestAvailableAudioFormat` (16 kHz Int16). Pushing Float32 crashes the app.
4. **Likely files:**
   - `AudioRecorder.swift`: pass buffers on to the live transcriber.
   - `TranscriptionCoordinator.swift`: start, stop and final pass.
   - `RecordingPanelView.swift` / `RecorderState.swift`: show the live text.
   - `SettingsManager.swift`: on/off setting and language.
   - `WhisperKitManager.swift`: stays the final pass.
5. **Measure in the real app:**
   - The delay before the first live words (the spike got ~1.1 s).
   - Total memory with live mode on.
   - Language list and behaviour on macOS 26, not just 27.
   - The Telugu model download, which shows no size.
6. **Spike code** is in `.superpowers/spikes/live-transcription/` (`spike.swift`, test recordings, raw output). It is git-ignored, so `git clean` deletes it. Copy anything worth keeping before cleaning.
