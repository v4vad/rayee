# Rayee

A local voice-to-text transcription app for macOS. Press a hotkey, speak, and text appears wherever you're typing.

## Features

- **100% Local** - All processing happens on your Mac. No internet required, fully private.
- **Global Hotkey** - Trigger from any app with a keyboard shortcut
- **Auto-paste** - Transcribed text goes directly where your cursor is
- **Multiple AI Models** - Choose between speed and accuracy
- **Custom Vocabulary** - Teach it names, jargon, and technical terms
- **Text Transformations** - Fix grammar, format as bullets, rephrase, change tone — all locally with Llama 3.2
- **History** - Search and access past transcriptions with transformation tracking
- **Voice Detection** - Automatically stops when you stop talking
- **Setup Guide** - First-launch checklist shows what's ready and what needs attention

## Text Transformations

After transcribing, transform your text with one click (or Cmd+1 through Cmd+5):

| Transform | Shortcut | What it does |
|-----------|----------|--------------|
| Grammar   | Cmd+1    | Fix spelling, grammar, and punctuation |
| Bullets   | Cmd+2    | Format as bullet points |
| Rephrase  | Cmd+3    | Rewrite in different words |
| Formal    | Cmd+4    | Make it sound professional |
| Casual    | Cmd+5    | Make it conversational |

Powered by Llama 3.2 1B (4-bit quantized via MLX). Runs entirely on Apple Silicon — no cloud, no API keys.

## Tech Stack

- **Swift/SwiftUI** - Native macOS interface
- **Python** - AI transcription engine
- **Faster-Whisper** - Fast, accurate speech recognition
- **MLX** - Apple Silicon-optimized LLM inference for text transformations

## Status

🚧 Under development

See [PLAN.md](PLAN.md) for the full development roadmap.

## Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon Mac recommended (M1/M2/M3/M4)
- Python 3.10+
- Xcode 15+

## License

TBD
