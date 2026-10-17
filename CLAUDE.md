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

## Text model eval

- Change prompts or text models only with eval evidence: `TEST_RUNNER_RAYEE_EVAL=1` (Settings models) or `TEST_RUNNER_RAYEE_EVAL_CANDIDATES=1` (candidates) on `xcodebuild test ... -only-testing:RayeeTests/ModelEvalTests`. Each run overwrites its results file in `docs/plans/` — back it up first.
- Any model that obeys dictated instructions (eval sample 8) is disqualified, whatever its score.
- Apple's on-device model needs Apple Intelligence turned on; otherwise it reports `modelNotReady`.
