# Smart Dictation — Handoff Notes
_Last updated: 2026-05-22_

## What was built

Feature: **Smart Dictation** — after each recording, the on-device LLM automatically cleans up the raw transcription (grammar fix, filler word removal, spoken punctuation conversion) without any button tap.

### Branch
`feat/smart-dictation-auto-transform`

### Files changed
| File | What changed |
|---|---|
| `swift/Rayee/Rayee/TransformationState.swift` | Added `TransformationType.smartDictation` case |
| `swift/Rayee/Rayee/MLXTransformManager.swift` | Added `.smartDictation` prompt in `buildPrompt()` |
| `swift/Rayee/Rayee/SettingsManager.swift` | Added `smartDictationEnabled` setting (default OFF) |
| `swift/Rayee/Rayee/TranscriptionCoordinator.swift` | Added `pendingSmartDictationPaste` — defers auto-paste when smart dictation is on |
| `swift/Rayee/Rayee/AppState.swift` | Auto-triggers transform after transcription; `thenPaste` logic; empty-output guard; `pasteAndHidePanel` helper |
| `swift/Rayee/Rayee/TransformationsSettingsTab.swift` | New "Smart Dictation" section with on/off toggle; `.smartDictation` filtered from Visible Transformations list |

### How it works
- After transcription, if `smartDictationEnabled && transformationsEnabled`, `handleTransformation(.smartDictation)` fires automatically
- Streaming preview UI is reused unchanged — user sees text build up and can accept/revert
- If auto-paste is also on: transform → paste result → hide panel. Fallback: if LLM fails or produces empty output, paste raw text
- Reverting in the preview cancels any deferred auto-paste

### What the prompt does (grammar-only)
- Fixes grammar, punctuation, and sentence structure
- Removes filler words (uh, um, like, you know)
- Converts spoken punctuation to symbols ("comma" → , "period" → .)
- Preserves the speaker's words exactly — does not rephrase or summarize

### What was considered and rejected
Voice command parsing ("scratch that", "next bullet", "delete that") was explored but dropped. A 1B model cannot reliably distinguish command phrases from the same words used as content (e.g. "next point of contact" vs "next point"). The failure mode — silently deleting or restructuring content the user didn't intend — is worse than not having the feature. Grammar-only cleanup is reliable; command parsing is not.

---

## What still needs doing

### 1. Open PR

Code is complete. Push and create the PR:
```bash
git push -u origin feat/smart-dictation-auto-transform
```
Then `gh pr create` or `/commit-push-pr`.

---

## Docs created this session
- `docs/brainstorms/2026-05-14-auto-transform-requirements.md` — requirements doc
- `docs/plans/2026-05-14-001-feat-smart-dictation-auto-transform-plan.md` — implementation plan (status: completed)
- `scripts/test_smart_dictation.py` — Ollama test harness (written for command-parsing validation; no longer needed for current scope)
