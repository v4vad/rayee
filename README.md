# Rayee

A local voice-to-text transcription app for macOS. Press a hotkey, speak, and text appears wherever you're typing.

## Install

1. Download **Rayee.dmg** from the [latest release](https://github.com/v4vad/rayee/releases/latest)
2. Open the DMG and drag Rayee to Applications
3. Launch Rayee — it lives in your menu bar
4. Grant microphone and accessibility permissions when prompted

**Requirements:** macOS 13+ (Ventura or later), Apple Silicon Mac (M1/M2/M3/M4)

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

Powered by Llama 3.2 1B (4-bit quantized via MLX). Runs entirely on Apple Silicon — no cloud, no API keys.

## How It Works

Rayee uses a two-component architecture:

- **Swift/SwiftUI frontend** — Native macOS menu bar app handling UI, hotkeys, and auto-paste
- **Python backend** — AI transcription engine using [Faster-Whisper](https://github.com/SYSTRAN/faster-whisper), bundled inside the app

The Swift app communicates with the Python server over a local Unix socket. Everything runs on your Mac.

## Building from Source

### Prerequisites
- macOS 13+, Apple Silicon
- Xcode 15+
- Python 3.10+

### Setup
```bash
# Python backend
cd python && python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Start the server (for development)
python run_server.py

# Swift app
open swift/Rayee/Rayee.xcodeproj
# Build and run from Xcode (Cmd+R)
```
