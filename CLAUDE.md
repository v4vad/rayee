# Rayee

Local voice-to-text transcription app for macOS. Pure native Swift — everything runs inside the app: no server, no sockets, no Python.

## Development Setup

WhisperKit and the MLX model download on first use.

## Build & Release

Use the `/publish-release` skill — it handles version bump, DMG build, EdDSA signing, appcast update, and GitHub release.

## Conventions

- Swift: no tabs, 4-space indent, SwiftUI for all views
- All user settings stored in UserDefaults via `SettingsManager`
- History stored in SQLite at `~/.rayee/history.db` (WAL mode, FULLMUTEX)
- Audio format everywhere: 16kHz, mono, Float32 PCM
