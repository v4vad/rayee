# Rayee Roadmap

## Next update

- **Notch recorder:** tighter corners (12 instead of 20 on the outer corners, matching the 12 where it meets the notch). On branch `feature/next-update`.
- **Docs:** cleaned up; finished plans removed (they're in git history).

## Next feature: in-place preview

Show the live words at the text cursor, in the app you're typing into, instead of only in the notch. The likely route is a macOS input method's temporary "marked text". Brainstorm first, then a quick spike in the apps the user dictates into most, before any real build.

## Known issues

- **Switching microphones mid-recording** (for example, AirPods switching to call mode when a Zoom or Meet call starts) probably stops the recording silently. Rayee doesn't yet react when the audio device changes. Untested.
- **A skipped clean-up that is stuck on a model download can't stop early.** Later clean-ups wait behind it until the download finishes.
- **"Pasted" can flash briefly** at the start of a new recording.
- **Preview language only downloads after Settings → Recording is opened.** On a Mac whose system language isn't English, there's no live preview until then.

## Hands-on checks

Things no unit test covers. Walk through [docs/manual-checks.md](docs/manual-checks.md) with a release build.

---

## Shipped

- **v0.10.3** (Oct 31, 2026): new app icon.
- **v0.10.2** (Oct 31): updates install by themselves after 2 minutes idle; no log file at all.
- **v0.10.1** (Oct 31): faster live words, fewer redraws, Settings restyled like System Settings, macOS 27's "Device Control and Data Access" name in warnings.
- **v0.10** (Oct 30): live preview of your words in the recorder (Apple's on-device recognizer); notch recorder; Settings sidebar; 5-step setup guide; Smart Dictation uses Apple Intelligence or Qwen3; dictations stay in order when one is still being cleaned up. Needs macOS 26.
- **v0.9** (Oct 15): large-v3 turbo speech model for new installs; choice of writing model; Smart Dictation cleans up instead of answering what you dictated.
- **v0.8** (Oct 15): errors shown instead of the panel silently closing; recordings up to 5 minutes; first word no longer clipped; clipboard put back after paste.
- **v0.4**: Python removed. One native Swift app with WhisperKit and mlx-swift-lm.
