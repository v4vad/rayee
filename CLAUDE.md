# Rayee

Local voice-to-text transcription app for macOS. Pure native Swift — everything runs inside the app: no server, no sockets, no Python.

## Docs

- `docs/how-it-works.md` — how a dictation flows, rules that must hold, the approved recorder look, key decisions
- `swift/Rayee/Rayee/CLAUDE.md` — which source file does what
- `ROADMAP.md` — next update, next feature, known issues, what shipped
- `docs/manual-checks.md` — hands-on checks to walk through with a release build
- `docs/eval/` — text model eval results (written by the eval tests)
- The repo is **public**: no personal paths, keys or private notes in committed files. Finished plans get deleted after shipping; git history keeps them.

## Development Setup

WhisperKit and the MLX model download on first use.

## Build & Release

- `main` is protected by a pre-commit hook: commit on a branch, open a PR, merge it.
- Use the `/publish-release` skill — it handles version bump, DMG build, EdDSA signing, appcast update, and GitHub release. Builds run only on this Mac (signing certificate and update key are in its Keychain).
- Run the tests with the `/run-tests` skill.

## Conventions

- Swift: no tabs, 4-space indent, SwiftUI for all views
- All user settings stored in UserDefaults via `SettingsManager`
- History stored in SQLite at `~/.rayee/history.db` (WAL mode, FULLMUTEX)
- Audio format everywhere: 16kHz, mono, Float32 PCM (except the live preview, which needs Int16)
- Minimum macOS is 26.0 (design refresh, Oct 2026)
- App source files are listed by hand in `project.pbxproj`: add/remove/rename them with `python3 -I scripts/xcodeproj_files.py add|remove|rename …` (test files in `RayeeTests/` need nothing)
- Test logs interleave lines, so grep counts of "passed" can be off by one — diff test names between runs instead
- With `-quiet` there's no `** TEST SUCCEEDED **` line: exit code 0 and no `' failed` test lines is the pass signal. The line `error: the following command failed with exit code 0 but produced no further output` is harmless
- `.claude/` is git-ignored, so edits to `.claude/skills/*/SKILL.md` live only on this Mac
- If tests hang at launch ("test runner hung"), look for piled-up `xcodebuild -runFirstLaunch` processes; a Mac restart cleared it

## Text model eval

- Change prompts or text models only with eval evidence: `TEST_RUNNER_RAYEE_EVAL=1` (Settings models) or `TEST_RUNNER_RAYEE_EVAL_CANDIDATES=1` (candidates) on `xcodebuild test ... -only-testing:RayeeTests/ModelEvalTests`. Results go to `docs/eval/model-eval-results.md` and `docs/eval/model-eval-candidates.md`; each run overwrites its file, so back it up first.
- Any model that obeys dictated instructions (eval sample 8) is disqualified, whatever its score.
- Apple's on-device model needs Apple Intelligence turned on; otherwise it reports `modelNotReady`.
