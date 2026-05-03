# Rayee Roadmap

## Completed: Eliminated Python — Pure Native App

**Shipped in v0.4.** Replaced the Python server with:
- WhisperKit (`argmax-oss-swift` v1.0.0) for CoreML transcription
- mlx-swift-lm v3.31.3 for Metal-accelerated LLM transforms

Single .app binary, no Python dependency, instant startup.

---

## Future: Live Transcription (Real-Time Streaming)

**Goal:** Text appears word-by-word as you speak — like Apple's built-in dictation.

**How:** WhisperKit has a built-in streaming transcription API. Feed audio chunks in real-time and display partial results as they arrive.

---

## Future Consideration: Upgrade LLM Model

**Current:** `mlx-community/Llama-3.2-1B-Instruct-4bit` — smallest capable instruct model (~800MB).

**Options:**
- `Llama-3.2-3B-Instruct-4bit` — better quality, ~2GB more RAM
- `Llama-3.3-8B-Instruct-4bit` — much better quality, ~5GB more RAM
- Llama 4 variants — latest generation

**Trade-off:** Better transform quality vs. more memory. Consider making this user-configurable like the Whisper model picker.
