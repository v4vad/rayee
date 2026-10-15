# Rayee

A local voice-to-text transcription app for macOS. Press a hotkey, speak, and text appears wherever you're typing.

## Install

1. Download **Rayee.dmg** from the [latest release](https://github.com/v4vad/rayee/releases/latest)
2. Open the DMG and drag Rayee to Applications
3. Launch Rayee — it lives in your menu bar
4. Grant microphone and accessibility permissions when prompted

**Requirements:** macOS 14.6 or later, Apple Silicon Mac (M1 or newer)

## Features

- **100% Local** - All processing happens on your Mac. No internet required, fully private.
- **Global Hotkey** - Trigger from any app with a keyboard shortcut (Option+Space by default)
- **Auto-paste** - Transcribed text goes directly where your cursor is
- **Multiple AI Models** - Choose between speed and accuracy (tiny, small, medium, large)
- **Custom Vocabulary** - Teach it names, jargon, and technical terms
- **Text Transformations** - Fix grammar, format as bullets, rephrase, change tone — all locally
- **History** - Search and access past transcriptions
- **Voice Detection** - Automatically stops when you stop talking

## Text Transformations

After transcribing, transform your text with one click (or Cmd+1 through Cmd+5):

| Transform | Shortcut | What it does |
|-----------|----------|--------------|
| Grammar   | Cmd+1    | Fix spelling, grammar, and punctuation |
| Bullets   | Cmd+2    | Format as bullet points |
| Rephrase  | Cmd+3    | Rewrite in different words |
| Formal    | Cmd+4    | Make it sound professional |
| Casual    | Cmd+5    | Make it conversational |

Transforms use an on-device text model you can choose in Settings (Llama 3.2 1B by default, or Qwen3 1.7B / 4B), 4-bit quantized via MLX. Runs entirely on Apple Silicon — no cloud, no API keys.

## How It Works

Rayee is a single native Swift app — no Python, no server.

- **Speech to text:** [WhisperKit](https://github.com/argmaxinc/WhisperKit) runs OpenAI's Whisper models on-device with Core ML.
- **Text transformations:** [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) runs a small language model on the Mac's GPU.
- Models download on first use. Speech models are stored in `~/.rayee`; the writing model is stored in the Hugging Face cache (`~/.cache/huggingface`).

## Building from Source

### Prerequisites
- macOS 14.6+, Apple Silicon
- Xcode 16+ with the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)

### Build and run
```bash
open swift/Rayee/Rayee.xcodeproj
# Press Cmd+R in Xcode
```
