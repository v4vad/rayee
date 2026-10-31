# Hands-on checks

Things the unit tests can't cover. Try them with a release build, tick what works, and fix or note what doesn't. Most of these have never been tried in the real app: the user chose (Oct 18, 2026) to test everything together with a later release.

## Recorder

- [ ] MacBook screen: the recorder grows out of the notch, and menu-bar icons beside the notch can still be clicked while it's open.
- [ ] The corners look right: smooth, 12 on every corner, nothing clipped.
- [ ] External monitor: the capsule appears on the screen with the pointer, with the same edge and shadow.
- [ ] Over a full-screen app, the recorder still shows.
- [ ] During a screen recording (⌘⇧5), the recorder doesn't appear in the video (best effort).

## Dictating and pasting

- [ ] Speak the instant you press the hotkey: the first word is in the transcript.
- [ ] Noisy room: Rayee still stops by itself after you stop talking.
- [ ] Dictating into TextEdit shows "Pasted", the shape retracts, and the text is there.
- [ ] Finder desktop in front: the Copy card appears and Return copies. Pressing the hotkey while the Copy card is open pastes into the previous app, without flicker.
- [ ] Esc while "Pasted" is showing reaches the app in front.
- [ ] Change the hotkey: the new one works, and the recorder and menu show it.

## Smart Dictation

- [ ] Dictate a question ("what time is the meeting tomorrow"): it comes back cleaned up, not answered.
- [ ] Start a second dictation during "Cleaning up": both texts are pasted, cleaned, in the order spoken.
- [ ] Esc during "Cleaning up": the raw text is pasted exactly once, and TextEdit doesn't beep.
- [ ] Discard while it's still writing: nothing gets pasted.

## Live preview

- [ ] English: grey words appear within about a second and turn white after a pause.
- [ ] Pause for 10 s mid-sentence: the recording keeps going, and new words follow on.
- [ ] Pause twice in one dictation: settled sentences are separated by a space (not "so.And").
- [ ] A dictation of 1 minute or more: only the last 2–3 lines show, and the recorder doesn't jitter.
- [ ] Smart Dictation on: the preview shows the raw words, and "Cleaning up" and the paste work as before.
- [ ] Switch it off: the recorder looks exactly as it does without the feature.
- [ ] Telugu: the first download shows progress, the preview is in English letters, and the paste is in Telugu script.

## Permissions and setup

- [ ] Microphone turned off in System Settings: the error appears with "Open Settings".
- [ ] Change a permission, then reopen the menu: the warning updates.
- [ ] Settings → About → Run Setup Again: all 5 steps work (mic bars move, Accessibility moves on by itself), and "Hello Rayee" lands in the practice box.

## Settings

- [ ] Sidebar: selecting items works and the window sizes sensibly. Opening a menu link while Settings is already open goes to the right page.
- [ ] History: the search field and filters show inside Settings.
