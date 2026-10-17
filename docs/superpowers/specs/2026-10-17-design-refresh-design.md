# Rayee design refresh — notch recorder, Settings, menu, onboarding

**Date:** 2026-10-17 · **Branch:** `feature/design-refresh` · **Status:** approved in chat, awaiting spec review

## Goal

Make Rayee feel like a native macOS 26 app:

- On notched MacBooks, the recorder grows down out of the notch.
- On other screens, the recorder becomes a matching floating capsule.
- Settings gets a sidebar with fewer, clearer sections.
- First-run setup becomes a guided, step-by-step flow.
- Features that no longer earn their place are removed.

## Decisions (from the brainstorm)

| # | Decision | Why |
|---|---|---|
| D1 | Minimum macOS becomes **26.0** | Liquid Glass everywhere and no fallback code. The Apple text model already needs 26. Older Macs keep v0.9. |
| D2 | The recorder grows **vertically**. Inside the menu-bar band it is never wider than the notch. | The user's menu bar is crowded, and sideways "wings" would cover icons. |
| D3 | **Quiet** content: a status glyph, a waveform and one-word labels. Text appears only when it can't be pasted. | Rayee is used dozens of times a day, so calm and fast wins. |
| D4 | **Remove the 5 manual rewrites** (Grammar, Bullets, Rephrase, Formal, Casual), the Format menu and the before/after preview | Smart Dictation already does cleanup automatically, so these are no longer needed (user agreed). |
| D5 | Settings moves to a **sidebar** with 7 sections, and the separate System Status window is removed | Matches macOS 26 System Settings. Today the status appears twice. |
| D6 | Onboarding becomes a **5-step flow** ending in a real "try it" dictation | The user sees success before leaving setup. |

References: DynamicNotchKit (MIT), boring.notch, VoiceInk and NotchDrop for notch mechanics; iPhone Dynamic Island and Live Activities for the state model; notch teleprompters (Notchie, NotchPrompter) for vertical columns under the notch, screen-capture hiding and hover-to-pause; Spotlight and Raycast for Esc-first keyboard handling; Apple Pay for the drawn checkmark; Wispr Flow's onboarding for the "try it" sandbox. Code may be studied, but no code is copied from the GPL apps (VoiceInk, boring.notch). DynamicNotchKit's MIT geometry helpers may be adapted, with attribution in a comment.

---

## 1. Notch recorder

### 1.1 Shape and geometry

- **Notch detection.** `screen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` both non-nil means the screen has a notch.
  - Notch width = `frame.width − left.width − right.width`.
  - Notch height = `safeAreaInsets.top`.
- **Two zones.**
  - *Menu-bar band* (from y = 0 to the notch height): the shape is exactly the notch width, plus 0 pt.
  - *Body* (below the band): up to **300 pt** wide, centred.
  - Where the body is wider than the notch, the join uses concave curves of about 10 pt radius, so the body appears to pour out of the notch.
- **Colour.** Pure black (`#000`) so it fuses with the camera housing. Text and glyphs are white, using system font sizes 13 and 11.
- **Bottom corners.** 22 pt radius when the shape is open, 14 pt when it is near-closed. Corner radii animate together with the height (boring.notch-style radius morph).
- **No notch** (external monitor, MacBook Air M1 and earlier, or a mirrored display):
  - The body is a black capsule floating **6 pt below the menu bar**, centred, with all four corners rounded at 22 pt and a soft shadow.
  - There is no band and no concave join.
  - The states and contents are the same.
- **Screen choice.** The recorder opens on the screen with the mouse pointer. If that fails it uses `NSScreen.main`, then `NSScreen.screens.first`. The screen is re-resolved each time recording starts, and geometry is recomputed on `NSApplication.didChangeScreenParametersNotification`.

### 1.2 Window

- It is an `NSPanel` subclass with style `[.borderless, .nonactivatingPanel]`.
- `isOpaque = false`, `backgroundColor = .clear` and `hasShadow = false` (the capsule draws its own shadow).
- `level = .statusBar + 1`, so it sits above the menu bar.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, so it shows over full-screen apps and never appears in Cmd-Tab.
- `sharingType = .none`, so it is hidden from screen recordings and screen sharing. This is best effort: some ScreenCaptureKit-based recorders may ignore it. If that happens, accept it and don't build workarounds.
- It must never steal focus from the app being dictated into:
  - `canBecomeKey` returns true **only** in the Result state, so Return and the Copy button work there.
  - In every other state it returns false.
- **Frame.** The window frame equals the current state's shape bounds plus a 20 pt shadow margin, top-aligned to the screen's top edge.
  - When growing, the window resizes first, then the shape animates.
  - When shrinking, the shape animates first, then the window resizes.
  - This keeps transparent areas from blocking clicks on the app below.
- One panel is kept for the app's lifetime and repositioned per session. If a stale-frame bug appears after sleep or wake, rebuild the panel per session, as VoiceInk does.

### 1.3 States

All body heights below are measured below the band, at a width of 300 pt (or the capsule width on non-notch screens).

| State | Body height | Shows | Interaction |
|---|---|---|---|
| **Hidden** | 0 | Nothing. The window is ordered out. | — |
| **Listening** | 44 | Left: a pulsing red dot. Centre: a live waveform (9 bars from `AudioLevelMonitor`). Right: a timer (`0:07`), shown after 3 s. | Click the shape to stop. The hotkey also stops. Esc cancels (existing global Esc handling). |
| **Transcribing** | 44 | The waveform settles into a slow flat shimmer line. Label: "Transcribing". | Esc does nothing (a transcription in progress finishes, as today). |
| **Cleaning up** | 44 | ✦ glyph plus "Cleaning up", with shimmer text. If the model is downloading: "Downloading model 45%". | Esc or a click: skip the cleanup and paste the raw text. |
| **Pasted** | 44 | A checkmark that draws as a stroke over 0.25 s, plus "Pasted". | Retracts into the notch after 0.8 s. |
| **Result** (nowhere to paste) | 64–140 | Up to 4 lines of the text (scrollable beyond that). A row with **Copy ↩** and **✕**. | Return = Copy and close. Esc or ✕ = close. Auto-closes after 20 s; hovering pauses the countdown. The text stays in History either way. |
| **Error** | 64–100 | An amber glyph, one plain sentence (from `UserFacingError`), and at most one action button (for example "Open Settings" for a blocked microphone). | Esc or ✕ closes. Auto-closes after 8 s unless hovered. |

When nothing needs reading, there is **no** "RAYEE" header, no "Ready" footer and no gear button.

### 1.4 Motion

- **Open:** `.spring(response: 0.42, dampingFraction: 0.80)` on height and radii. Content fades in 0.09 s after the shape starts growing.
- **Between states:** height springs with the same curve, and content cross-fades over 0.15 s. Text never reflows during the animation: each state's content is laid out at its final size.
- **Close:** `.spring(response: 0.45, dampingFraction: 1.0)`, a slightly faster ease with no bounce, retracting up into the notch (or fading up on the capsule).
- **Reduce Motion:** opacity fades only, with no springs or shimmer.
- **Haptics:** a light `NSHapticFeedbackManager` tick on Pasted and Error, for trackpad users.
- Existing start, stop and error sounds are unchanged.

### 1.5 Settings hook

General → **Recorder style**:

- **Automatic** (default): notch on notched screens, capsule elsewhere.
- **Floating capsule**: the capsule everywhere.

---

## 2. Settings window

- `NavigationSplitView` with a sidebar. The window is about 720 × 500 and resizable.
- Content uses `Form { }.formStyle(.grouped)`. Liquid Glass comes from the system; no custom glass is applied to content.
- The existing `settingsTab` deep link keeps working, mapped to the new section ids.

| Section (SF Symbol) | Contents |
|---|---|
| **General** (`gearshape`) | **Status card** at the top: green "Ready to dictate", or a list of problems, each with a Fix button (mic, accessibility, model missing or loading). Then: hotkey, auto-paste, sounds, recorder style, **launch at login** (`SMAppService.mainApp`). |
| **Recording** (`waveform`) | "Stop after silence" slider (5–60 s, as today). "Noisy room mode" (today's adaptive silence detection, renamed with a plain footer). The 5-minute safety limit is always on and its switch is removed. |
| **Smart Dictation** (`wand.and.sparkles`) | On/off switch. Writing model picker (Automatic / Apple / Qwen 1.7B / Qwen 4B) with the existing "Currently: …" note and status row. |
| **Speech Model** (`cpu`) | The 3 recommended WhisperKit models as rows (existing `ModelRow`), with "Show all models" revealing the rest (standard plus distil). |
| **Dictionary** (`character.book.closed`) | Today's Vocabulary tab, restyled as a `Form` list with an add field. |
| **History** (`clock.arrow.circlepath`) | Today's History view, restyled. |
| **About** (`info.circle`) | App icon, version, Check for Updates, Run Setup Again, Reset to Defaults. |

**Removed:**

- The "Enable text transformations" master switch. `smartDictationEnabled` alone decides. On upgrade, if `transformationsEnabled` was false, `smartDictationEnabled` is set to false once, so behaviour doesn't change silently.
- The "Visible Transformations" list.
- The "Recording timeout" switch. The 5-minute limit is always on; the old key is ignored.
- The duplicate "AI Model: Ready" row.
- The System Status window (`Window(id: "setup-guide")` as a status checker). Its job moves to the status card.

## 3. Menu-bar menu

1. *(Only when something is wrong)* "⚠ Microphone is off — Fix…" (or the most important problem). Opens Settings → General.
2. **Record** / **Stop Recording**, with the configured hotkey shown.
3. —
4. History…
5. Settings… ⌘,
6. Check for Updates…
7. —
8. Quit Rayee ⌘Q

Removed: Vocabulary… and System Status…. The menu-bar icon states are unchanged.

## 4. Onboarding

- A single window of about 520 × 560 with no title bar chrome.
- It has 5 steps with progress dots at the bottom, plus Back and Continue buttons (`.glassProminent` for the primary button).
- It appears on first launch, keeping the existing `hasCompletedSetup` flag and the launch-time trigger in `MenuBarLabel`, and again from About → Run Setup Again.

| Step | Content | Moves on when |
|---|---|---|
| 1. Welcome | App icon, "Talk, and Rayee types.", "Everything stays on this Mac." **The speech model starts downloading in the background now.** | Get Started |
| 2. Microphone | One-line reason and an [Allow Microphone] button. Once allowed, a live level meter labelled "Say something" appears. | Permission granted. Continue is enabled. |
| 3. Accessibility | "So Rayee can paste into your apps and hear your hotkey." [Open System Settings]. Rayee polls every 1 s. If permission is granted but the hotkey tap still fails, it shows a "Quit and reopen Rayee" hint. | Granted (moves on by itself), or **Skip**: Rayee will copy instead of paste. |
| 4. Speech Model | Model name, size, and a progress bar. Usually already done. | Download finished and model loaded |
| 5. Try It | The hotkey shown (changeable through the existing `HotkeyPickerView`), a practice text field focused, and "Press ⌥Space and say 'Hello Rayee'". The real recorder runs. When text lands in the field, a checkmark appears. Smart Dictation on/off switch. | Finish sets `hasCompletedSetup = true` |

---

## 5. Code impact

**New files.** Each needs a line in `project.pbxproj`, because app sources are listed by hand.

- `NotchGeometry.swift`: notch detection, sizes, screen choice. Pure functions, so it can be unit-tested.
- `NotchShape.swift`: an animatable `Shape` covering the band, the concave join and the body.
- `RecorderState.swift`: the state enum and pure transition rules, also unit-testable.
- `OnboardingView.swift`: replaces `SetupGuideView.swift`.
- `SettingsSections.swift`, or reuse of the existing tab files renamed: the new sidebar sections.

**Rewritten:**

- `RecordingPanelController.swift`: becomes the notch panel controller.
- `RecordingPanelView.swift`: becomes the recorder view.
- `SettingsView.swift`: becomes the sidebar.
- `GeneralSettingsTab.swift`
- `TransformationsSettingsTab.swift`: becomes Smart Dictation.
- `ModelsSettingsTab.swift`
- `VocabularySettingsTab.swift`
- `SimpleMenuView.swift`
- `RayeeApp.swift`: scene changes.

**Deleted:**

- `TransformationPreviewView.swift`
- `SetupGuideView.swift`
- From `TransformationType`: the cases `grammar`, `bullets`, `rephrase`, `formal` and `casual`, plus their prompts. Only `smartDictation` remains, so the enum may collapse.
- `TransformationState`'s preview fields.
- `enabledTransformations` and `transformationsEnabled`, after the one-time migration above.
- `timeoutEnabled` and its UI.
- `PillButtonStyle` and any other button styles left unused.
- Most of the `Config.recordingPanel*` size constants.

**Project:** `MACOSX_DEPLOYMENT_TARGET` goes from 14.6 to 26.0 in all 4 build configurations, and `#available` checks for 26 are removed.

**Behaviour that must not change:**

- Paste and clipboard restore.
- Smart Dictation's paste-after-cleanup and cancel-means-no-paste rules.
- History saving of the cleaned text.
- Esc cancelling a recording.
- The start, stop and error sounds.

## 6. Testing

- **Unit tests**, new, in `RayeeTests/`:
  - `NotchGeometryTests`: notch math with fake screen rectangles, the no-notch fallback, and the screen-choice fallback chain.
  - `RecorderStateTests`: every transition, including cancel during cleanup leading to no paste, and the auto-dismiss timers being paused by hover.
  - The settings migration (`transformationsEnabled = false` leads to `smartDictationEnabled = false`).
- **Existing tests** are updated wherever they reference removed transform types or settings. All tests must pass.
- **Manual checks (by the user):**
  1. MacBook screen: the recorder grows from the notch, and menu-bar icons beside the notch stay uncovered.
  2. External monitor: the capsule appears on the screen with the mouse.
  3. A full-screen app: the recorder is still visible.
  4. Dictating into a text field: it shows Pasted, then retracts.
  5. No text field (Finder desktop): the Result card appears, and Return copies.
  6. Microphone blocked: the Error state shows with Open Settings.
  7. A screen recording (Cmd-Shift-5) doesn't show the recorder.
  8. Onboarding from About → Run Setup Again goes from start to finish.

## 7. Out of scope

- Live transcription (Phase 4, v1.0).
- Custom Smart Dictation "modes".
- An always-visible idle indicator.
- Hover-to-open on the notch.
- Per-app settings.
