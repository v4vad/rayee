# Rayee Roadmap

## Completed: live transcription

- While you dictate, your words appear in the notch recorder about a second after you say them
- Grey words are a draft; they turn white once settled (usually after a pause)
- The pasted text still comes from Whisper, so Smart Dictation, Vocabulary and History work as before
- Settings → Recording: "Show words while I speak" (on by default) and "Preview language" (English (India) by default; Telugu and others download once)
- Uses Apple's built-in speech recognizer, which runs outside Rayee, so Rayee uses no extra memory

---

## Completed: design refresh

- The recorder grows out of the notch at the top of the screen (a floating capsule on screens without a notch)
- Settings has a sidebar: General, Recording, Smart Dictation and About
- The menu-bar menu is leaner and shows a warning when something stops Rayee from working
- Setup is a 5-step guide, replacing the System Status window
- Minimum macOS is now 26

---

## Completed: v0.8 reliability release

- Errors (like a blocked microphone) now show in the panel instead of it silently closing
- Recordings can run up to 5 minutes (was 1 minute)
- The first word is no longer clipped, and audio is never repeated
- Your clipboard is put back after auto-paste
- Smart Dictation saves the cleaned text to History, and Discard really stops it

---

## Completed: Eliminated Python — Pure Native App

**Shipped in v0.4.** Replaced the Python server with:
- WhisperKit (`argmax-oss-swift` v1.0.0) for CoreML transcription
- mlx-swift-lm v3.31.3 for Metal-accelerated LLM transforms

Single .app binary, no Python dependency, instant startup.

---

## Future Consideration: Upgrade LLM Model

**Current:** `mlx-community/Llama-3.2-1B-Instruct-4bit` — smallest capable instruct model (~800MB).

**Options:**
- `Llama-3.2-3B-Instruct-4bit` — better quality, ~2GB more RAM
- `Llama-3.3-8B-Instruct-4bit` — much better quality, ~5GB more RAM
- Llama 4 variants — latest generation

**Trade-off:** Better transform quality vs. more memory. Consider making this user-configurable like the Whisper model picker.
