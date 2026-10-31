# Rayee

A local voice-to-text app for macOS. Press a hotkey, speak, and your words are typed wherever your cursor is. Everything runs on your Mac.

## Install

1. Download **Rayee.dmg** from the [latest release](https://github.com/v4vad/rayee/releases/latest)
2. Open the DMG and drag Rayee to Applications
3. Launch Rayee. It lives in your menu bar, and a short setup guide walks you through the rest
4. Allow the microphone, and Accessibility (called **Device Control and Data Access** on macOS 27) so Rayee can paste for you

**Requirements:** macOS 26 or later, Apple Silicon Mac (M1 or newer)

Rayee updates itself: new versions download in the background and install when you're not dictating.

## Features

- **Private** - Speech and text models run on your Mac. Nothing you say leaves it, and Rayee keeps no log of what you dictate. The internet is only needed to download models and updates.
- **Global hotkey** - Start and stop from any app (Option+Space by default)
- **Notch recorder** - A small recorder grows out of the notch while you dictate (a floating capsule on screens without a notch)
- **Live preview** - See your words in the recorder as you speak (English, Telugu and more, using macOS's own recognizer)
- **Auto-paste** - The text goes where your cursor is. When there's nowhere to paste, Rayee shows it with a Copy button, and your clipboard is put back afterwards
- **Smart Dictation** - Optional clean-up after each recording: punctuation, capitals and filler words like "um", without changing what you said
- **Dictionary** - Teach it names, jargon and technical terms
- **History** - Search and copy past dictations
- **Stops by itself** - Recording ends when you stop talking for a while (you choose how long), or press the hotkey again

## Models

- **Speech:** [WhisperKit](https://github.com/argmaxinc/WhisperKit) runs OpenAI's Whisper on-device. Rayee recommends Whisper large-v3 turbo (about 630 MB) on M2 and newer, and you can pick a smaller one in Settings → Speech Model.
- **Smart Dictation:** Apple Intelligence when it's turned on, otherwise Qwen3 4B (Macs with 16 GB or more) or Qwen3 1.7B, run with [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm). You can choose in Settings → Smart Dictation.
- Models download the first time they're used. Speech models are stored in `~/.rayee`; the Qwen models in the Hugging Face cache (`~/.cache/huggingface`).

## Building from source

Rayee is a single native Swift app: no server, no Python.

### Prerequisites
- macOS 26+, Apple Silicon
- Xcode 26+ with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)

### Build and run
```bash
open swift/Rayee/Rayee.xcodeproj
# Press Cmd+R in Xcode
```

### Run the tests
```bash
xcodebuild test -project swift/Rayee/Rayee.xcodeproj -scheme Rayee -destination 'platform=macOS'
```
