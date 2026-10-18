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
- Minimum macOS is 26.0 (design refresh, Oct 2026)
- App source files are listed by hand in `project.pbxproj`: add/remove/rename them with `python3 -I scripts/xcodeproj_files.py add|remove|rename …` (test files in `RayeeTests/` need nothing)
- Test logs interleave lines, so grep counts of "passed" can be off by one — diff test names between runs instead
- This Xcode's test log has no "Executed N tests" line — `** TEST SUCCEEDED **` is the pass signal
- `.claude/` is git-ignored, so edits to `.claude/skills/publish-release/SKILL.md` live only on this Mac
- If tests hang at launch ("test runner hung"), look for piled-up `xcodebuild -runFirstLaunch` processes; a Mac restart cleared it

## Text model eval

- Change prompts or text models only with eval evidence: `TEST_RUNNER_RAYEE_EVAL=1` (Settings models) or `TEST_RUNNER_RAYEE_EVAL_CANDIDATES=1` (candidates) on `xcodebuild test ... -only-testing:RayeeTests/ModelEvalTests`. Each run overwrites its results file in `docs/plans/` — back it up first.
- Any model that obeys dictated instructions (eval sample 8) is disqualified, whatever its score.
- Apple's on-device model needs Apple Intelligence turned on; otherwise it reports `modelNotReady`.
