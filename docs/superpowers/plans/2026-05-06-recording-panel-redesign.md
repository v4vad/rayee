# Recording Panel Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing floating recording panel with the redesigned dark panel — new background, SF Pro typography, live waveform visualization, and an expandable Format options surface — matching the Figma spec at `bNiHS2i14QOseHRvYBZqQC`.

**Architecture:** `RecordingPanelView` is a complete visual rewrite; the callback interface is extended with `onDone`/`onDiscard` to separate result-state dismissal from recording cancellation. `RecordingPanelController` gains a recording timer and a `isFormatExpanded` flag. Config is updated for the new 400px-wide panel dimensions. Settings changes (TabView, Settings scene, MenuBarExtra) are **already committed** on `feature/ui-redesign` — this plan does not touch them.

**Tech Stack:** SwiftUI, AppKit (NSWindow), SF Pro (system font), SF Symbols, AudioLevelMonitor (already exists).

**Branch:** `feature/ui-redesign` — all tasks commit to this branch.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `swift/Rayee/Rayee/Config.swift` | Modify | Panel dimensions, waveform bar count |
| `swift/Rayee/Rayee/TransformationState.swift` | Modify | Correct SF Symbol names for Grammar and Casual |
| `swift/Rayee/Rayee/PanelButtonStyles.swift` | Modify | New button styles: blue pill, gray pill, icon button, ghost text |
| `swift/Rayee/Rayee/RecordingPanelController.swift` | Modify | Recording timer, format expanded state, onDone/onDiscard callbacks |
| `swift/Rayee/Rayee/RecordingPanelView.swift` | Rewrite | All visual states of the floating panel |

---

## Task 1: Update Config dimensions and waveform count

**Files:**
- Modify: `swift/Rayee/Rayee/Config.swift`

- [ ] **Step 1: Update the Recording Panel section in Config.swift**

Replace the entire `// MARK: - Recording Panel` section with:

```swift
// MARK: - Recording Panel

/// Corner radius for the floating panel
static let panelCornerRadius: CGFloat = 12

/// Width of the floating recording panel
static let recordingPanelWidth: CGFloat = 400

/// Height — Idle state
static let recordingPanelHeight: CGFloat = 100

/// Height — Recording state (waveform visible)
static let recordingPanelHeightRecording: CGFloat = 164

/// Height — Transcribing state
static let recordingPanelHeightTranscribing: CGFloat = 108

/// Height — Result state, format options collapsed
static let recordingPanelHeightWithResult: CGFloat = 193

/// Height — Result state, format options expanded
static let recordingPanelHeightResultExpanded: CGFloat = 366

/// Height of the panel when showing transformation preview (TransformationPreviewView)
static let recordingPanelHeightWithTransform: CGFloat = 420

/// Number of waveform bars (matches Figma design)
static let waveformBarCount = 27
```

- [ ] **Step 2: Build to confirm no regressions**

In Xcode: `Cmd+B`. Expected: Build Succeeded. The only things that reference `recordingPanelHeight` and `waveformBarCount` are `RecordingPanelController.swift` and `AudioLevelMonitor.swift` — both still compile since the constant names are unchanged (we only added new ones and changed values).

- [ ] **Step 3: Commit**

```bash
git add swift/Rayee/Rayee/Config.swift
git commit -m "config: update recording panel dimensions for redesign (400px wide, state-specific heights)"
```

---

## Task 2: Fix SF Symbol names in TransformationState

**Files:**
- Modify: `swift/Rayee/Rayee/TransformationState.swift`

The spec uses `checkmark.circle` for Grammar and `bubble.left` for Casual. The current code has `textformat.abc` and `face.smiling` respectively.

- [ ] **Step 1: Update systemImage computed property**

Find the `var systemImage: String` computed property and replace it:

```swift
var systemImage: String {
    switch self {
    case .grammar:  return "checkmark.circle"
    case .bullets:  return "list.bullet"
    case .rephrase: return "arrow.triangle.2.circlepath"
    case .formal:   return "briefcase"
    case .casual:   return "bubble.left"
    }
}
```

- [ ] **Step 2: Build**

`Cmd+B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add swift/Rayee/Rayee/TransformationState.swift
git commit -m "fix: update SF Symbol names for Grammar (checkmark.circle) and Casual (bubble.left)"
```

---

## Task 3: Update PanelButtonStyles for the new design

**Files:**
- Modify: `swift/Rayee/Rayee/PanelButtonStyles.swift`

Current file has one style (`PillButtonStyle`). Replace the entire file with four styles: blue pill, gray pill, icon button, ghost text.

- [ ] **Step 1: Rewrite PanelButtonStyles.swift**

```swift
//
//  PanelButtonStyles.swift
//  Rayee
//
//  Button styles for the floating recording panel.
//

import SwiftUI

// MARK: - Blue pill (Done, primary action)

struct BluePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(
                Capsule().fill(Color(hex: 0x0A84FF).opacity(configuration.isPressed ? 0.7 : 1.0))
            )
    }
}

// MARK: - Gray pill (Copy, secondary action)

struct GrayPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .default, weight: .medium))
            .foregroundColor(.white.opacity(0.82))
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
    }
}

// MARK: - Icon button (Format toggle)

struct IconButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(isActive ? 0.14 : (configuration.isPressed ? 0.12 : 0.07)))
            )
    }
}

// MARK: - Ghost text (Discard)

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.2 : 0.35))
    }
}

// MARK: - Legacy pill (kept for any remaining callers)

struct PillButtonStyle: ButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isProminent
                    ? Color(hex: 0x0A84FF).opacity(configuration.isPressed ? 0.7 : 1.0)
                    : Color.white.opacity(configuration.isPressed ? 0.12 : 0.07)
                )
            )
            .foregroundColor(isProminent ? .white : .white.opacity(0.82))
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex         & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Previews

#Preview("Button styles") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            Button("Done") {}
                .buttonStyle(BluePillButtonStyle())
            Button("Copy") {}
                .buttonStyle(GrayPillButtonStyle())
            Button(action: {}) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.70))
            }
            .buttonStyle(IconButtonStyle(isActive: false))
            Button("Discard") {}
                .buttonStyle(GhostButtonStyle())
        }
        HStack(spacing: 12) {
            Button(action: {}) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.70))
            }
            .buttonStyle(IconButtonStyle(isActive: true))
        }
    }
    .padding(24)
    .background(Color(hex: 0x1C1C1E))
}
```

- [ ] **Step 2: Build**

`Cmd+B`. Expected: Build Succeeded. `PillButtonStyle` is kept for backward compat so existing callers still compile.

- [ ] **Step 3: Commit**

```bash
git add swift/Rayee/Rayee/PanelButtonStyles.swift
git commit -m "feat: new panel button styles — blue pill, gray pill, icon, ghost"
```

---

## Task 4: Extend RecordingPanelController with timer and format state

**Files:**
- Modify: `swift/Rayee/Rayee/RecordingPanelController.swift`

- [ ] **Step 1: Add published properties**

After the existing `@Published var showResult = false` line, add:

```swift
/// Whether the Format options panel is expanded in result state
@Published var isFormatExpanded = false

/// Elapsed recording duration in seconds (drives the timer display)
@Published var recordingDuration: TimeInterval = 0
```

- [ ] **Step 2: Add private timer property**

After the `let transformState = TransformationState()` line, add:

```swift
private var recordingTimer: Timer?
```

- [ ] **Step 3: Add onDone and onDiscard callbacks**

After the existing `var onTransform: ((TransformationType) -> Void)?` line, add:

```swift
/// Called when user taps Done in result state (accept + dismiss)
var onDone: (() -> Void)?

/// Called when user taps Discard in result state (dismiss without action)
var onDiscard: (() -> Void)?
```

- [ ] **Step 4: Update setRecording to start/stop the timer**

Replace the existing `setRecording` method:

```swift
func setRecording(_ recording: Bool) {
    isRecording = recording
    if recording {
        audioLevelMonitor.reset()
        showResult = false
        isFormatExpanded = false
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
        }
    } else {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    updateWindowSize()
}
```

- [ ] **Step 5: Update hidePanel to reset format state and invalidate timer**

Replace the existing `hidePanel` method:

```swift
func hidePanel() {
    window?.orderOut(nil)
    showResult = false
    isFormatExpanded = false
    transcribedText = ""
    recordingDuration = 0
    recordingTimer?.invalidate()
    recordingTimer = nil
    transformState.reset()
}
```

- [ ] **Step 6: Update updateWindowSize to handle all height cases**

Replace the existing `updateWindowSize` method:

```swift
private func updateWindowSize() {
    guard let window = window else { return }

    let newHeight: CGFloat
    if transformState.showPreview || transformState.isTransforming {
        newHeight = Config.recordingPanelHeightWithTransform
    } else if showResult && isFormatExpanded {
        newHeight = Config.recordingPanelHeightResultExpanded
    } else if showResult {
        newHeight = Config.recordingPanelHeightWithResult
    } else if isTranscribing {
        newHeight = Config.recordingPanelHeightTranscribing
    } else if isRecording {
        newHeight = Config.recordingPanelHeightRecording
    } else {
        newHeight = Config.recordingPanelHeight
    }

    var frame = window.frame
    let heightDiff = newHeight - frame.height
    frame.size.height = newHeight
    frame.origin.y -= heightDiff
    window.setFrame(frame, display: true, animate: true)
}
```

- [ ] **Step 7: Wire onDone/onDiscard in RecordingPanelHostView**

In `RecordingPanelHostView.body`, after the existing `onCopy:` argument, add the new callbacks. Also pass `isFormatExpanded` binding and `recordingDuration`. Find the `RecordingPanelView(...)` call and update it (full call shown in Task 5, Step 1 — keep the controller calls in sync).

For now, add to the existing call site in RecordingPanelHostView:

```swift
onDone: {
    controller.onDone?()
},
onDiscard: {
    controller.onDiscard?()
},
isFormatExpanded: $controller.isFormatExpanded,
recordingDuration: controller.recordingDuration,
```

And wire `onDone`/`onDiscard` in AppState or wherever `RecordingPanelController` is configured. In `AppState.swift`, find where `panelController.onCancel` is set and add:

```swift
panelController.onDone = { [weak self] in
    self?.panelController.hidePanel()
}
panelController.onDiscard = { [weak self] in
    self?.panelController.hidePanel()
}
```

- [ ] **Step 8: Build**

`Cmd+B`. Expected: Build Succeeded (RecordingPanelView will fail to compile until Task 5 because the new parameters don't exist yet — that's OK, fix in Task 5).

- [ ] **Step 9: Commit**

```bash
git add swift/Rayee/Rayee/RecordingPanelController.swift
git commit -m "feat: add recording timer, format expanded state, onDone/onDiscard to panel controller"
```

---

## Task 5: Rewrite RecordingPanelView — structure and Idle state

**Files:**
- Modify: `swift/Rayee/Rayee/RecordingPanelView.swift`

This task establishes the shell: dark background, top highlight, header layer, and the Idle-specific footer. Subsequent tasks fill in each state's content zone.

- [ ] **Step 1: Replace the entire file**

```swift
//
//  RecordingPanelView.swift
//  Rayee
//
//  Floating recording panel — all states.
//  Design spec: docs/superpowers/specs/2026-05-06-rayee-ui-redesign.md
//

import SwiftUI

struct RecordingPanelView: View {
    let isRecording: Bool
    let isTranscribing: Bool
    @ObservedObject var audioLevelMonitor: AudioLevelMonitor
    @Binding var transcribedText: String
    let showResult: Bool
    @Binding var isFormatExpanded: Bool
    let recordingDuration: TimeInterval
    var onStop: () -> Void
    var onCancel: () -> Void
    var onDone: () -> Void
    var onDiscard: () -> Void
    var onSettings: () -> Void
    var onCopy: () -> Void
    var transformState: TransformationState?
    var transformationsEnabled: Bool
    var enabledTransformations: Set<String>
    var onTransform: ((TransformationType) -> Void)?
    var onUseTransformed: ((String) -> Void)?
    var onUseOriginal: (() -> Void)?

    // MARK: - Design tokens

    private let panelBg    = Color(hex: 0x1C1C1E)
    private let headerBg   = Color(hex: 0x242426)
    private let accentGreen = Color(hex: 0x30D158)
    private let accentRed   = Color(hex: 0xFF453A)
    private let accentBlue  = Color(hex: 0x0A84FF)

    var body: some View {
        ZStack(alignment: .top) {
            // Panel background
            RoundedRectangle(cornerRadius: Config.panelCornerRadius)
                .fill(panelBg)

            // Panel border: 0.75px white 9%
            RoundedRectangle(cornerRadius: Config.panelCornerRadius)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)

            VStack(spacing: 0) {
                // Top highlight — 1px glass edge
                Color.white.opacity(0.06)
                    .frame(height: 1)

                // Header
                headerView
                    .frame(height: 51)
                    .background(headerBg)

                // Divider
                Color.white.opacity(0.08).frame(height: 1)

                // State-specific content
                contentView

                // Footer / Actions (not shown in Transcribing)
                if !isTranscribing || showResult || isRecording {
                    Color.white.opacity(0.08).frame(height: 1)
                    footerView
                }
            }
        }
        .frame(width: Config.recordingPanelWidth)
        .clipShape(RoundedRectangle(cornerRadius: Config.panelCornerRadius))
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 0) {
            // RAYEE wordmark
            Text("RAYEE")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(.white)
                .tracking(0.5)
                .padding(.leading, 20)

            Spacer()

            // Right context — state-specific
            Group {
                if isRecording {
                    Text(timerString(recordingDuration))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.45))
                } else if showResult {
                    Text("just now")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.45))
                } else if !isTranscribing {
                    Text("Option + Space to record")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.trailing, 20)
        }
    }

    // MARK: - Content zone

    @ViewBuilder
    private var contentView: some View {
        if let tState = transformState, tState.isActive {
            TransformationPreviewView(
                transformState: tState,
                onUseTransformed: { text in onUseTransformed?(text) },
                onUseOriginal: { onUseOriginal?() }
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        } else if showResult {
            resultContent
        } else if isRecording {
            waveformContent
        } else if isTranscribing {
            transcribingContent
        }
        // Idle state has no content zone — header + footer only
    }

    // MARK: - Footer / Actions

    @ViewBuilder
    private var footerView: some View {
        if showResult {
            resultActions
                .frame(height: 46)
        } else if isRecording {
            recordingFooter
                .frame(height: 29)
        } else {
            idleFooter
                .frame(height: 46)
        }
    }

    // MARK: - Idle footer

    private var idleFooter: some View {
        HStack {
            Text("Ready")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(accentGreen)
                .padding(.leading, 20)

            Spacer()

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
        }
    }

    // MARK: - Timer helper

    private func timerString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Placeholder content (filled in Tasks 6–8)

    @ViewBuilder
    private var waveformContent: some View {
        // Task 6
        Color.clear.frame(height: 80)
    }

    @ViewBuilder
    private var recordingFooter: some View {
        // Task 6
        HStack {
            Text("Recording")
                .font(.system(size: 13))
                .foregroundColor(accentRed)
                .padding(.leading, 20)
            Spacer()
        }
    }

    @ViewBuilder
    private var transcribingContent: some View {
        // Task 7
        Color.clear.frame(height: 54)
    }

    @ViewBuilder
    private var resultContent: some View {
        // Task 8
        Text(transcribedText)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.white.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private var resultActions: some View {
        // Task 8
        HStack(spacing: 8) {
            Button("Done", action: onDone).buttonStyle(BluePillButtonStyle())
            Button("Copy", action: onCopy).buttonStyle(GrayPillButtonStyle())
            Spacer()
            Button("Discard", action: onDiscard).buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Previews

#Preview("Idle") {
    RecordingPanelView(
        isRecording: false, isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant(""), showResult: false,
        isFormatExpanded: .constant(false), recordingDuration: 0,
        onStop: {}, onCancel: {}, onDone: {}, onDiscard: {},
        onSettings: {}, onCopy: {},
        transformState: nil, transformationsEnabled: false, enabledTransformations: []
    )
    .padding(24).background(Color.black)
}

#Preview("Result") {
    RecordingPanelView(
        isRecording: false, isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant("Meeting tomorrow at three pm. Don't forget to bring the quarterly report and the updated client list."),
        showResult: true,
        isFormatExpanded: .constant(false), recordingDuration: 0,
        onStop: {}, onCancel: {}, onDone: {}, onDiscard: {},
        onSettings: {}, onCopy: {},
        transformState: TransformationState(), transformationsEnabled: true,
        enabledTransformations: Set(TransformationType.allCases.map(\.rawValue))
    )
    .padding(24).background(Color.black)
}
```

- [ ] **Step 2: Fix RecordingPanelHostView call site**

In `RecordingPanelController.swift`, update the `RecordingPanelView(...)` call in `RecordingPanelHostView.body` to pass the new parameters. The full updated call:

```swift
RecordingPanelView(
    isRecording: controller.isRecording,
    isTranscribing: controller.isTranscribing,
    audioLevelMonitor: controller.audioLevelMonitor,
    transcribedText: $controller.transcribedText,
    showResult: controller.showResult,
    isFormatExpanded: $controller.isFormatExpanded,
    recordingDuration: controller.recordingDuration,
    onStop: { controller.onStop?() },
    onCancel: { controller.onCancel?() },
    onDone: { controller.onDone?() },
    onDiscard: { controller.onDiscard?() },
    onSettings: {
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    },
    onCopy: { controller.onCopy?() },
    transformState: controller.transformState,
    transformationsEnabled: SettingsManager.shared.transformationsEnabled,
    enabledTransformations: SettingsManager.shared.enabledTransformations,
    onTransform: { type in controller.onTransform?(type) },
    onUseTransformed: { text in controller.onUseTransformed?(text) },
    onUseOriginal: { controller.onUseOriginal?() }
)
```

- [ ] **Step 3: Wire onDone/onDiscard in AppState**

In `AppState.swift`, find where other `panelController.on*` callbacks are set (e.g. `panelController.onCancel = ...`) and add:

```swift
panelController.onDone = { [weak self] in
    self?.panelController.hidePanel()
}
panelController.onDiscard = { [weak self] in
    self?.panelController.hidePanel()
}
```

- [ ] **Step 4: Build**

`Cmd+B`. Expected: Build Succeeded.

- [ ] **Step 5: Verify Idle state in Xcode Preview**

Open `RecordingPanelView.swift`, click the `#Preview("Idle")` canvas. Confirm:
- Dark `#1C1C1E` background
- "RAYEE" wordmark left-aligned, SF Pro Semibold
- "Option + Space to record" right-aligned, dimmed
- Divider line visible between header and footer
- "Ready" in green bottom-left, gear icon bottom-right

- [ ] **Step 6: Commit**

```bash
git add swift/Rayee/Rayee/RecordingPanelView.swift swift/Rayee/Rayee/RecordingPanelController.swift swift/Rayee/Rayee/AppState.swift
git commit -m "feat: recording panel shell — dark background, header, Idle state"
```

---

## Task 6: Waveform visualization and Recording state

**Files:**
- Modify: `swift/Rayee/Rayee/RecordingPanelView.swift`

- [ ] **Step 1: Replace waveformContent with the live waveform view**

Replace the `waveformContent` computed property (currently a `Color.clear` placeholder) with:

```swift
@ViewBuilder
private var waveformContent: some View {
    ZStack {
        // Soft glow bloom behind the bars
        Ellipse()
            .fill(Color.white.opacity(0.035))
            .frame(width: 220, height: 40)
            .blur(radius: 12)

        // Live bars from AudioLevelMonitor
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(audioLevelMonitor.levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.90))
                    .frame(width: 2.5, height: barHeight(for: level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
    }
    .frame(height: 80)
}

private func barHeight(for level: Float) -> CGFloat {
    // Map 0...1 RMS level to 4...44pt bar height
    let clamped = max(0.001, min(1.0, level))
    let normalized = CGFloat(clamped)
    return 4 + normalized * 40
}
```

- [ ] **Step 2: Replace recordingFooter with the full recording footer**

Replace the placeholder `recordingFooter` with:

```swift
@ViewBuilder
private var recordingFooter: some View {
    HStack {
        Text("Recording")
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(accentRed)
            .padding(.leading, 20)

        Spacer()

        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(accentRed)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
    }
}
```

- [ ] **Step 3: Add Recording preview**

Add below the existing `#Preview("Result")`:

```swift
#Preview("Recording") {
    let monitor = AudioLevelMonitor()
    // Simulate a waveform with random levels
    for _ in 0..<27 { monitor.addLevel(Float.random(in: 0.05...0.9)) }
    return RecordingPanelView(
        isRecording: true, isTranscribing: false,
        audioLevelMonitor: monitor,
        transcribedText: .constant(""), showResult: false,
        isFormatExpanded: .constant(false), recordingDuration: 7,
        onStop: {}, onCancel: {}, onDone: {}, onDiscard: {},
        onSettings: {}, onCopy: {},
        transformState: nil, transformationsEnabled: false, enabledTransformations: []
    )
    .padding(24).background(Color.black)
}
```

- [ ] **Step 4: Build and verify preview**

`Cmd+B`. Open `#Preview("Recording")` canvas. Confirm:
- 27 bars of varying heights visible
- "Recording" red label bottom-left
- Stop icon (red square) bottom-right
- Timer shows "0:07" in header right

- [ ] **Step 5: Commit**

```bash
git add swift/Rayee/Rayee/RecordingPanelView.swift
git commit -m "feat: live waveform visualization in Recording state"
```

---

## Task 7: Transcribing state

**Files:**
- Modify: `swift/Rayee/Rayee/RecordingPanelView.swift`

- [ ] **Step 1: Replace transcribingContent with the real implementation**

Replace the placeholder `transcribingContent`:

```swift
@ViewBuilder
private var transcribingContent: some View {
    HStack {
        Text("Transcribing...")
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.white.opacity(0.82))
            .padding(.leading, 20)

        Spacer()

        // Indeterminate progress bar styled to match design
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 3)

                // Animated fill
                Capsule()
                    .fill(accentBlue)
                    .frame(width: geo.size.width * progressFraction, height: 3)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: progressFraction)
            }
        }
        .frame(width: 84, height: 3)
        .padding(.trailing, 20)
        .onAppear { progressFraction = 0.75 }
    }
    .frame(height: 54)
}
```

- [ ] **Step 2: Add @State for progress animation**

Inside the `RecordingPanelView` struct, before the `body` computed property, add:

```swift
@State private var progressFraction: CGFloat = 0.1
```

- [ ] **Step 3: Update footerView — no footer in Transcribing state**

The current `footerView` already gates on `isTranscribing`. Verify that the condition `if !isTranscribing || showResult || isRecording` correctly hides the divider and footer when transcribing. Adjust to:

```swift
if !isTranscribing {
    Color.white.opacity(0.08).frame(height: 1)
    footerView
}
```

- [ ] **Step 4: Add Transcribing preview**

```swift
#Preview("Transcribing") {
    RecordingPanelView(
        isRecording: false, isTranscribing: true,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant(""), showResult: false,
        isFormatExpanded: .constant(false), recordingDuration: 0,
        onStop: {}, onCancel: {}, onDone: {}, onDiscard: {},
        onSettings: {}, onCopy: {},
        transformState: nil, transformationsEnabled: false, enabledTransformations: []
    )
    .padding(24).background(Color.black)
}
```

- [ ] **Step 5: Build and verify**

`Cmd+B`. Open `#Preview("Transcribing")`. Confirm:
- "Transcribing..." left-aligned, white 82%
- Animated blue progress bar right-aligned
- No divider or footer below content

- [ ] **Step 6: Commit**

```bash
git add swift/Rayee/Rayee/RecordingPanelView.swift
git commit -m "feat: Transcribing state with animated progress bar"
```

---

## Task 8: Result state — expandable Format options

**Files:**
- Modify: `swift/Rayee/Rayee/RecordingPanelView.swift`

- [ ] **Step 1: Replace resultContent with the full implementation**

Replace the placeholder `resultContent`:

```swift
@ViewBuilder
private var resultContent: some View {
    VStack(spacing: 0) {
        // Transcription text
        Text(transcribedText)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(.white.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .textSelection(.enabled)

        // Format options — shown when expanded
        if isFormatExpanded && transformationsEnabled {
            Color.white.opacity(0.08).frame(height: 1)
            formatOptionsView
        }
    }
}

private var formatOptionsView: some View {
    VStack(spacing: 0) {
        ForEach(TransformationType.allCases) { type in
            if enabledTransformations.contains(type.rawValue) {
                Button(action: { onTransform?(type) }) {
                    HStack {
                        Image(systemName: type.systemImage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.50))
                            .frame(width: 16, alignment: .center)

                        Text(type.displayName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.82))

                        Spacer()

                        Text("⌘\(type.shortcutNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }
    .padding(.vertical, 6)
}
```

- [ ] **Step 2: Add keyboard shortcut handling**

After the `formatOptionsView` declaration, add a view modifier to `resultContent`. At the bottom of the `body` stack, attach `.onKeyPress` or use `focusable` + key commands. The cleanest approach for a non-focused floating panel is to attach a keyboard shortcut on each format row. Update `formatOptionsView` button to:

```swift
Button(action: { onTransform?(type) }) {
    // ... same label as above ...
}
.buttonStyle(.plain)
.keyboardShortcut(KeyEquivalent(Character(String(type.shortcutNumber))), modifiers: .command)
```

- [ ] **Step 3: Replace resultActions with the full action bar (Format button included)**

Replace the placeholder `resultActions`:

```swift
@ViewBuilder
private var resultActions: some View {
    HStack(spacing: 8) {
        Button("Done", action: onDone)
            .buttonStyle(BluePillButtonStyle())

        Button("Copy", action: onCopy)
            .buttonStyle(GrayPillButtonStyle())

        if transformationsEnabled {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isFormatExpanded.toggle()
                }
            }) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.70))
            }
            .buttonStyle(IconButtonStyle(isActive: isFormatExpanded))
        }

        Spacer()

        Button("Discard", action: onDiscard)
            .buttonStyle(GhostButtonStyle())
    }
    .padding(.horizontal, 20)
}
```

- [ ] **Step 4: Make window height animate when format expands**

The `isFormatExpanded` binding is owned by `RecordingPanelController`. When it changes, `updateWindowSize()` must fire. In `RecordingPanelController`, add a `didSet` on `isFormatExpanded`:

```swift
@Published var isFormatExpanded = false {
    didSet { updateWindowSize() }
}
```

- [ ] **Step 5: Add Result Expanded preview**

```swift
#Preview("Result — Format Expanded") {
    RecordingPanelView(
        isRecording: false, isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant("Meeting tomorrow at three pm. Don't forget to bring the quarterly report and the updated client list."),
        showResult: true,
        isFormatExpanded: .constant(true), recordingDuration: 0,
        onStop: {}, onCancel: {}, onDone: {}, onDiscard: {},
        onSettings: {}, onCopy: {},
        transformState: TransformationState(), transformationsEnabled: true,
        enabledTransformations: Set(TransformationType.allCases.map(\.rawValue)),
        onTransform: { _ in }
    )
    .padding(24).background(Color.black)
}
```

- [ ] **Step 6: Build and verify all previews**

`Cmd+B`. Check all four previews (Idle, Recording, Transcribing, Result, Result–Format Expanded). Confirm:
- Format button appears in Result actions (only when transformations enabled)
- Tapping Format button in preview toggles `isFormatExpanded`
- Format options rows show symbol + label + ⌘N badge
- No layout overflow or clipping

- [ ] **Step 7: Commit**

```bash
git add swift/Rayee/Rayee/RecordingPanelView.swift swift/Rayee/Rayee/RecordingPanelController.swift
git commit -m "feat: Result state with expandable Format options and full action bar"
```

---

## Task 9: End-to-end manual test

No code changes. Run the app and exercise each state.

- [ ] **Step 1: Start the Python server**

```bash
cd /Users/karthikvadlapatla/claude/rayee/python
source venv/bin/activate
python -c "from rayee.startup import run_server; run_server()"
```

- [ ] **Step 2: Launch the app from Xcode** (`Cmd+R`)

- [ ] **Step 3: Verify Idle state**

Menu bar icon appears. Panel shows via hotkey (Option+Space). Check:
- Dark panel, 400px wide
- "RAYEE" wordmark left, "Option + Space to record" right
- "Ready" green + gear icon in footer

- [ ] **Step 4: Verify Recording state**

Press hotkey to start recording. Check:
- Waveform bars animate with voice
- Timer increments "0:01", "0:02"…
- "Recording" red label + stop icon in footer
- Panel is ~164px tall

- [ ] **Step 5: Verify Transcribing state**

Stop recording. Check:
- "Transcribing…" + animated blue bar
- No footer
- Panel is ~108px tall

- [ ] **Step 6: Verify Result state**

After transcription completes. Check:
- Transcribed text displayed
- Done (blue) + Copy (gray) + Format (icon, if transforms enabled) + Discard visible
- Done dismisses the panel
- Discard dismisses the panel
- Copy puts text on clipboard

- [ ] **Step 7: Verify Format expansion**

Tap Format button. Check:
- Panel animates to ~366px tall
- 5 format rows visible with symbols and ⌘1–⌘5 badges
- Tapping a format row triggers the transform (TransformationPreviewView appears)
- Format button active state (brighter fill) when expanded

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit -m "test: manual verification — all panel states confirmed on device"
```

---

## Self-Review Checklist

**Spec coverage:**
- ✅ Idle: wordmark, hint, Ready label, gear icon
- ✅ Recording: timer, waveform bars, glow, Recording label, stop button
- ✅ Transcribing: label, animated progress bar, no footer
- ✅ Result collapsed: text body, Done/Copy/Format/Discard actions
- ✅ Result expanded: Format options list, 5 rows, keyboard shortcuts
- ✅ Design tokens: #1C1C1E bg, #242426 header, accent colors
- ✅ 1px top highlight glass edge
- ✅ 0.75px border white 9%
- ✅ SF Pro throughout (system font via `.font(.system(...))`)
- ✅ Settings fixes: already committed — not in this plan
- ⚠️  Waveform glow: implemented as blur ellipse — matches spec intent, exact blur radius may need tuning

**Placeholder scan:** No TBDs remaining.

**Type consistency:** `TransformationType.shortcutNumber` used in Task 8 — this property already exists in `TransformationState.swift` (returns Int 1–5). `TransformationType.displayName` also exists. No mismatches.
