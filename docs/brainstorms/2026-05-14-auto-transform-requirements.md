---
date: 2026-05-14
topic: smart-dictation
---

# Smart Dictation — Command-Aware Auto-Transform

## Problem Frame
Today, Rayee transcribes exactly what you say — every filler word, every correction attempt, every structural instruction. After recording, you must manually click a transform button to clean things up. This adds friction and loses the intent behind spoken editing commands like "next point" or "remove that."

Smart Dictation makes the LLM act as an intelligent editor: it reads the raw transcription, distinguishes content from spoken commands, executes those commands, and delivers clean, structured text automatically — without any button clicks.

## Requirements

- R1. After transcription completes, if Smart Dictation is enabled, the LLM automatically processes the raw transcription — no button click needed.
- R2. The LLM distinguishes spoken content from spoken commands. Commands are executed; the remaining content is kept and cleaned up (grammar fixed). Only the final result is shown — not the raw dictation.
- R3. Supported command types the LLM must recognise and act on:
  - **Structure**: "next point", "new paragraph", "new line" → creates bullet points, paragraph breaks, numbered items
  - **Remove**: "remove that", "delete the last sentence", "scratch that" → removes the preceding content
  - **Replace/adjust**: "change X to Y", "actually [corrected version]", "make that formal/casual" → rewrites the specified portion
  - **Format**: "make that a heading", "bold that" → applies Markdown formatting
- R4. The transform uses the same live-streaming preview UI as manual transforms: the panel stays open, text streams in word by word. The user can cancel mid-stream or accept/revert the result.
- R5. If auto-paste is also enabled: the pipeline is transcribe → smart-dictation transform → paste the result. If the LLM fails or times out, fall back to pasting the raw transcription.
- R6. A single on/off toggle in Settings → Transformations controls this feature. Default is OFF (opt-in).

## Success Criteria
- A user can say *"Call Sarah tomorrow next point buy milk next point remove buy milk"* in one recording and get a two-item bullet list: "Call Sarah tomorrow" and "Buy milk" — without touching any button.
- Spoken content that happens to contain words like "remove" or "next" but is clearly not a command (e.g., "write a note about how to remove paint") is transcribed as-is, not misinterpreted.
- When auto-paste is on, the clean transformed text (not raw dictation) lands in the focused app. If the LLM fails, raw text is pasted so nothing is lost.

## Scope Boundaries
- Smart Dictation replaces the simpler fixed-type auto-transform. There is no separate "always apply Grammar Fix" toggle — the single Smart Dictation toggle covers both grammar cleanup and command execution.
- Manual transform buttons (Grammar, Bullets, Rephrase, Formal, Casual) remain available and unchanged for users who prefer to transform after reviewing the raw transcription.
- No real-time / mid-recording command processing — commands are interpreted after the full recording ends.
- Format commands produce Markdown output (e.g., `**bold**`, `# Heading`). Rich-text or HTML output is out of scope.

## Key Decisions
- **One LLM pass for everything**: Grammar cleanup + command execution happen in a single prompt. This is simpler, faster, and more coherent than chaining multiple transforms.
- **Streaming preview, not silent**: Keeps the user in the loop; reuses existing tested UI; allows cancellation. Silent background mode is a future consideration.
- **Toggle-only settings**: No need to configure command types — the LLM handles all of them automatically from context.
- **Markdown for formatting**: Aligns with how transforms already work today and is universally pasteable.

## Dependencies / Assumptions
- Smart Dictation only fires when `transformationsEnabled` (master toggle) is also on.
- The LLM (Llama 3.2 1B on-device) is capable enough to reliably distinguish content from commands in typical short dictations (30 seconds or less). This assumption should be validated during planning.

## Outstanding Questions

### Resolve Before Planning
*(none)*

### Deferred to Planning
- [Affects R1][Technical] What happens if the LLM model isn't loaded when Smart Dictation fires? Investigate `MLXTransformManager` warm-up timing — does the panel show a loading state, or does it fail fast and fall back to raw text?
- [Affects R2][Needs research] Is Llama 3.2 1B (4-bit quantised) reliable enough for command disambiguation on short dictations, or do we need a fallback prompt strategy? Consider testing with ambiguous phrases before committing.
- [Affects R4][Technical] The existing `TransformationPreviewView` expects a manually initiated transform. Confirm it can be entered automatically and that "Use This" / "Original" still behave correctly in the auto-triggered path.
- [Affects R3][Technical] Decide the system prompt design for command recognition — what phrasing produces the best results with the on-device model at temperature 0.

## Decision (2026-05-22)

**Voice command execution (R3) was dropped before shipping.**

Testing against Llama 3.2 1B showed the model cannot reliably distinguish command phrases from content (e.g. "next point of contact" triggered a bullet). The failure mode — silently deleting or restructuring text the user didn't intend — was judged worse than not having the feature.

**What shipped:** Grammar cleanup + filler word removal only (R1, R2 partially, R4, R5, R6). The feature is implemented as `TransformationType.smartDictation` with a grammar-only prompt. Command execution may be revisited with a larger model.
