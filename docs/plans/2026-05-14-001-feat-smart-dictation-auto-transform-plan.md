---
title: "feat: Smart Dictation — grammar auto-clean after transcription"
type: feat
status: completed
date: 2026-05-14
decision: 2026-05-22
origin: docs/brainstorms/2026-05-14-auto-transform-requirements.md
note: Voice command execution was dropped — shipped as grammar-only cleanup. See brainstorm doc for rationale.
---

# feat: Smart Dictation — Command-Aware Auto-Transform

## Overview

Add a "Smart Dictation" mode that automatically processes raw transcriptions with the on-device LLM after every recording — without any button click. The LLM both fixes grammar and executes inline voice commands (e.g. "next point", "remove that", "make that a heading") in a single pass.

## Problem Statement / Motivation

Today users must manually click a transform button after every recording. Users who consistently want grammar fixes or use voice editing commands ("next point", "scratch that") have to do this every single time. Smart Dictation eliminates that friction. See [origin document](../brainstorms/2026-05-14-auto-transform-requirements.md).

## Proposed Solution

Introduce a new `TransformationType.smartDictation` that fires automatically after transcription completes, controlled by a single on/off toggle in Settings → Transformations. The existing streaming preview UI is reused unchanged — the only difference is that the transform starts without a user tap.

**Pipeline when Smart Dictation is ON:**
- Only smart dictation → transcribe → LLM transform → panel stays open with streaming preview → user accepts/reverts
- Smart dictation + auto-paste → transcribe → LLM transform (streaming preview shown) → on completion, auto-paste transformed text → panel hides. If transform fails, fall back to pasting raw text.

## Implementation Order

### Phase 0: Validate the prompt FIRST (do this before any other code)

Before writing any Swift, validate that Llama 3.2 1B can actually handle the command disambiguation. If it can't, the prompt needs iteration — no point building the wiring around a broken prompt.

**How:** Temporarily swap the Grammar button's prompt to the Smart Dictation prompt (one line in `buildPrompt()`). Test these 20 phrases manually:

| Category | Phrase | Expected outcome |
|---|---|---|
| Unambiguous command | "Call Sarah tomorrow next point buy milk" | Two-bullet list |
| Unambiguous command | "I need to finish the report actually make it Monday" | "I need to finish the report by Monday" |
| Command-like content | "write a note about how to remove paint from a wall" | Transcribed verbatim (cleaned grammar) |
| Command-like content | "the next point of contact is Bob" | Transcribed verbatim |
| Mixed | "Meeting at 3pm scratch that meeting at 4pm" | "Meeting at 4pm" |

If accuracy on the "command-like content" rows is < 90%, iterate the prompt before proceeding. Revert the one-line swap after testing.

---

## Technical Approach

Six files require changes, in dependency order:

---

### 1. `TransformationState.swift` — Add new enum case

**File:** `swift/Rayee/Rayee/TransformationState.swift`

Add `smartDictation` to `TransformationType`. Handle it in all existing switch statements:

- **`label`**: `"Smart Dictation"` (shown in streaming preview header)
- **`icon`**: `"wand.and.sparkles"`
- **`shortcutNumber`**: omit (not a manual button — return `nil` or any unused number)

**Important:** `TransformationType.allCases` populates the "Visible Transformations" checkboxes in settings. Exclude `.smartDictation` from that list to prevent it appearing as a toggle-able button type. In `TransformationsSettingsTab`, filter the `ForEach` with `type != .smartDictation`.

---

### 2. `MLXTransformManager.swift` — Add smart dictation prompt

**File:** `swift/Rayee/Rayee/MLXTransformManager.swift`

Add a case to `buildPrompt(text:type:)` (currently around line 61). This is a `nonisolated static func` — the most important code to get right. Temperature stays at `0.0`.

```swift
case .smartDictation:
    system = "You are a voice dictation processor. Receive raw speech and output only the final clean text. No explanations."
    user = """
        Process this dictated speech. Apply both steps:
        1. Fix grammar, punctuation, and natural phrasing.
        2. Execute inline voice commands (remove the command words from the output):
           - "next point" / "new bullet" → start a new bullet: -
           - "new paragraph" / "new line" → insert a paragraph break
           - "remove that" / "scratch that" / "delete that" → remove the preceding sentence or phrase
           - "actually [text]" → replace the preceding clause with [text]
           - "make that a heading" → format preceding text as a Markdown heading (#)
           - "bold that" → wrap preceding text in **bold**
           - "make that formal" → rewrite preceding clause in formal tone
           - "make that casual" → rewrite preceding clause in casual tone
        Output only the final result with all commands applied.

        Text: \(text)
        """
```

**Note:** The system prompt is returned as part of the tuple — if this case needs a custom system, `buildPrompt` already returns `(system: String, user: String)` so both can be overridden.

---

### 3. `SettingsManager.swift` — Add `smartDictationEnabled`

**File:** `swift/Rayee/Rayee/SettingsManager.swift`

Follow the exact three-step `autoPasteEnabled` pattern:

```swift
// Step 1 — in SettingsKey enum (line ~25)
static let smartDictationEnabled = "smartDictationEnabled"

// Step 2 — @Published property (line ~234)
@Published var smartDictationEnabled: Bool {
    didSet { UserDefaults.standard.set(smartDictationEnabled, forKey: SettingsKey.smartDictationEnabled) }
}

// Step 3 — in init() (line ~353)
if UserDefaults.standard.object(forKey: SettingsKey.smartDictationEnabled) != nil {
    self.smartDictationEnabled = UserDefaults.standard.bool(forKey: SettingsKey.smartDictationEnabled)
} else {
    self.smartDictationEnabled = false  // opt-in, default OFF per R6
}

// Step 4 — in resetToDefaults()
smartDictationEnabled = false
```

---

### 4. `AppState.swift` — Wire the auto-trigger

**File:** `swift/Rayee/Rayee/AppState.swift`

In `handleTranscriptionResult(_:)`, the hook point is **after `showResultMode(text:)` is called** (currently line ~253). At that point `recordingPanelController.transcribedText` is already set.

```swift
// EXISTING (lines 253–259):
if !didPaste && !text.isEmpty {
    recordingPanelController.showResultMode(text: text)
    // ↓ ADD THIS
    if SettingsManager.shared.smartDictationEnabled
        && SettingsManager.shared.transformationsEnabled {
        handleTransformation(type: .smartDictation)
    }
} else if didPaste {
    recordingPanelController.hidePanel()
}
```

**Auto-paste + Smart Dictation interaction (R5):**

When both are enabled, suppress the immediate auto-paste and instead paste the LLM result. Use the `TranscriptionCoordinator` pattern — it already owns `pendingAutoPaste`, so a sibling flag lives naturally there:

**a) In `TranscriptionCoordinator`** — when `settings.smartDictationEnabled && settings.transformationsEnabled && settings.autoPasteEnabled`, skip the immediate paste. Pass `didPaste: false` to `onTranscriptionComplete`. Add `var pendingSmartDictationPaste = false` alongside `pendingAutoPaste`.

**b) In `AppState.handleTranscriptionResult`** — read `transcriptionCoordinator.pendingSmartDictationPaste`. If true, pass `thenPaste: true` to `handleTransformation`.

**c) In `handleTransformation(type:thenPaste:Bool = false)`** — after `transformState.completeTransformation(...)`:
  - If `thenPaste && !streamingText.isEmpty`: call `PasteManager.shared.paste(text: streamingText)` → hide panel
  - If `thenPaste && streamingText.isEmpty`: fall back to pasting the raw text → hide panel
  - In the `catch` block: if `thenPaste`, paste raw text and hide panel (existing fallback wired to paste)

**Cancel during streaming (when auto-paste is pending):** If the user presses Escape mid-stream, the existing cancel path fires. In that path, if `pendingSmartDictationPaste` is true, paste the raw text and hide — same as failure fallback. Do not paste the partial streamed result.

The method stays `private`. No visibility change needed.

---

### 5. `TransformationsSettingsTab.swift` — Add the toggle

**File:** `swift/Rayee/Rayee/TransformationsSettingsTab.swift`

Add a new `Section` inside the `if settings.transformationsEnabled` guard, before the existing `Section("Model")`:

```swift
Section("Smart Dictation") {
    Toggle("Auto-clean after transcription", isOn: $settings.smartDictationEnabled)
} footer: {
    Text("Fixes grammar and runs your voice commands automatically after every recording — no tapping required.")
}
```

Also filter `.smartDictation` from the "Visible Transformations" `ForEach`:

```swift
ForEach(TransformationType.allCases.filter { $0 != .smartDictation }) { type in
    // existing toggle rows
}
```

---

### 6. Empty-output guard in `handleTransformation`

**File:** `swift/Rayee/Rayee/AppState.swift`

The LLM may return empty output if the input is entirely commands with no content (e.g. "delete that" with nothing preceding it). The `catch` block won't fire — this is a *successful* but empty response. Add an explicit guard in the success path:

```swift
// In the Task { } block, after completeTransformation:
let result = transformState.streamingText
if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    // Treat empty output as failure — keep raw text
    transformState.failTransformation(message: "No output produced")
    if thenPaste { PasteManager.shared.paste(text: rawText); recordingPanelController.hidePanel() }
} else {
    transformState.completeTransformation(transformedText: result)
    if thenPaste { PasteManager.shared.paste(text: result); recordingPanelController.hidePanel() }
}
```

(`rawText` is the original text captured at the top of `handleTransformation` — capture it as a local before calling `streamTransform`.)

---

### 7. History preservation note

`HistoryManager` saves the **raw transcription** when `transcribedText` is set (in `handleTranscriptionResult`). This happens before any transform. So the raw dictation — including all command words — is always recoverable from history even if the LLM removes content. No changes to `HistoryManager` needed, and no SQLite schema changes are required.

---

### 8. Model warm-up consideration

**No new code required** for the initial implementation. `MLXTransformManager.streamTransform()` already calls `loadModelIfNeeded()` internally and blocks until load succeeds or fails. The panel stays open with `transformState.isTransforming = true` during load + streaming, so the user sees the indicator.

**Optional enhancement (defer to follow-up):** When `smartDictationEnabled` is turned on in settings, call `MLXTransformManager.shared.loadModelIfNeeded()` proactively to warm the model before the first recording. This would make the first use feel instant rather than delayed. Not required for v1.

---

## System-Wide Impact

- **Interaction graph:** Recording ends → `TranscriptionCoordinator.onTranscriptionComplete` fires → `AppState.handleTranscriptionResult` → `showResultMode` → (NEW) `handleTransformation(.smartDictation)` → `MLXTransformManager.streamTransform` → tokens stream into `transformState` → `TransformationPreviewView` renders. The chain is the same as manual transforms; only the trigger is new.
- **Error propagation:** If `streamTransform` throws (model not loaded, timeout), the existing `catch` block in `handleTransformation` calls `transformState.failTransformation(message:)` — the preview shows an error state. The pending-paste fallback must be wired here too.
- **State lifecycle:** `transformState` is reset at the start of each recording (`startTranscription` path). No orphaned state risk.
- **API surface parity:** Manual transform buttons remain unchanged. Smart Dictation runs the same underlying `handleTransformation` path.

## Acceptance Criteria

- [ ] Recording "Call Sarah tomorrow next point buy milk" produces a two-bullet result without any button tap when Smart Dictation is enabled
- [ ] Recording "I need to finish the report by Friday actually make it next Monday" outputs "I need to finish the report by next Monday"
- [ ] Recording "write a note about how to remove paint from a wall" outputs clean grammar, **not** an edited result (command disambiguation)
- [ ] When Smart Dictation is OFF, behavior is identical to today — no transform fires automatically
- [ ] When Smart Dictation is OFF and master `transformationsEnabled` is OFF, Smart Dictation also does not fire
- [ ] With both Smart Dictation and auto-paste enabled: transformed text is pasted; if LLM fails, raw text is pasted
- [ ] A single on/off toggle appears in Settings → Transformations, default OFF
- [ ] `.smartDictation` does not appear as a button in the transform bar or in the "Visible Transformations" settings list
- [ ] The streaming preview UI looks and behaves identically to manually-triggered transforms

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Llama 3.2 1B (4-bit) misidentifies content as commands | Medium | Test with 10+ ambiguous phrases before shipping; adjust prompt if needed |
| Model cold-load delay (~3-5s) on first recording of the session | High (expected) | Panel stays open with spinner; acceptable for v1. Pre-warm is a follow-up. |
| LLM produces empty output when input is pure commands with no content | Low | Add guard: if `streamingText.isEmpty` after completion, fall back to raw text |
| Auto-paste + Smart Dictation interaction complexity | Medium | Follow the `pendingAutoPaste` pattern already in TranscriptionCoordinator |

## Sources & References

- **Origin document:** [docs/brainstorms/2026-05-14-auto-transform-requirements.md](../brainstorms/2026-05-14-auto-transform-requirements.md)
  - Key decisions carried forward: (1) one LLM pass for grammar + commands, (2) streaming preview not silent, (3) Grammar-style setting toggle default OFF
- `AppState.handleTranscriptionResult()`: `swift/Rayee/Rayee/AppState.swift:244–271`
- `AppState.handleTransformation()`: `swift/Rayee/Rayee/AppState.swift:309–334`
- `MLXTransformManager.buildPrompt()`: `swift/Rayee/Rayee/MLXTransformManager.swift:61–81`
- `MLXTransformManager.loadModelIfNeeded()`: `swift/Rayee/Rayee/MLXTransformManager.swift:86–112`
- `SettingsManager.autoPasteEnabled` pattern: `swift/Rayee/Rayee/SettingsManager.swift:234,353`
- `TransformationsSettingsTab.swift`: `swift/Rayee/Rayee/TransformationsSettingsTab.swift`
- `TransformationType` enum: `swift/Rayee/Rayee/TransformationState.swift:12–51`
