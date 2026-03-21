# Rayee Roadmap

## Blocked: Eliminate Python — Pure Native App

**Goal:** Replace the Python server with native Swift libraries. Single .app binary, no Python dependency, instant startup, ~40-50% less memory.

**Plan:** WhisperKit for transcription + mlx-swift-lm for LLM transforms.

**Status:** Attempted and reverted. Blocked by a dependency conflict:
- WhisperKit requires `swift-transformers` 1.1.6 to <1.2.0
- mlx-swift-lm requires `swift-transformers` 1.2.0 to <1.3.0
- These ranges don't overlap — SPM cannot resolve both in the same project
- No public project has made these two libraries coexist
- GitHub issue to be filed on WhisperKit requesting they widen the constraint

**When resolved, the plan is:**
1. Replace Python transcription with WhisperKit (native CoreML inference)
2. Replace Python transforms with mlx-swift-lm (native Metal LLM inference)
3. Delete all Python infrastructure (PythonBridge, ServerManager, HealthMonitor, etc.)

**Alternative if needed:** SwiftWhisper (whisper.cpp wrapper, 772 stars) + llmfarm_core (llama.cpp wrapper, 279 stars). Both have zero `swift-transformers` dependency. Community-maintained, not Apple.

---

## Blocked: Live Transcription (Real-Time Streaming)

**Goal:** Text appears word-by-word as you speak — like Apple's built-in dictation.

**Status:** Depends on the native migration above. WhisperKit has built-in streaming mode. With the current Python architecture, this would require WebSocket audio streaming + incremental Whisper processing — complex and would be thrown away during migration.

**When the native migration is done:** Use WhisperKit's streaming transcription API to feed audio chunks in real-time and display partial results.

---

## Future Consideration: Upgrade LLM Model

**Current:** `mlx-community/Llama-3.2-1B-Instruct-4bit` — smallest capable instruct model (~800MB).

**Options:**
- `Llama-3.2-3B-Instruct-4bit` — better quality, ~2GB more RAM
- `Llama-3.3-8B-Instruct-4bit` — much better quality, ~5GB more RAM
- Llama 4 variants — latest generation

**Trade-off:** Better transform quality vs. more memory. Consider making this user-configurable like the Whisper model picker.
