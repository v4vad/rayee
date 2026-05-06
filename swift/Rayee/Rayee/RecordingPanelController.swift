//
//  RecordingPanelController.swift
//  Rayee
//
//  Manages the floating NSWindow that contains the recording panel.
//  Creates a borderless, draggable window that floats above other apps.
//

import SwiftUI
import AppKit

/// Controller for the floating recording panel window
class RecordingPanelController: ObservableObject {
    /// The floating window
    private var window: NSWindow?

    /// Audio level monitor (shared with the view)
    let audioLevelMonitor = AudioLevelMonitor()

    /// Current recording state
    @Published var isRecording = false

    /// Current transcribing state
    @Published var isTranscribing = false

    /// Transcribed text to display (for result mode)
    @Published var transcribedText = ""

    /// Whether to show result mode (editable text + copy button)
    @Published var showResult = false

    /// Whether the Format options panel is expanded in result state
    @Published var isFormatExpanded = false {
        didSet { updateWindowSize() }
    }

    /// Elapsed recording duration in seconds (drives the timer display)
    @Published var recordingDuration: TimeInterval = 0

    /// Transformation state
    let transformState = TransformationState()

    private var recordingTimer: Timer?

    /// Callbacks
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSettings: (() -> Void)?
    var onCopy: (() -> Void)?
    var onTransform: ((TransformationType) -> Void)?
    var onUseTransformed: ((String) -> Void)?
    var onUseOriginal: (() -> Void)?

    /// Called when user taps Done in result state (accept + dismiss)
    var onDone: (() -> Void)?

    /// Called when user taps Discard in result state (dismiss without action)
    var onDiscard: (() -> Void)?

    // MARK: - Public Methods

    /// Show the recording panel centered on screen
    func showPanel() {
        if window == nil {
            createWindow()
        }

        updateWindowSize()
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Ensure it's above all other windows
        window?.level = .floating
    }

    /// Hide the recording panel
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

    /// Update recording state
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

    /// Update transcribing state
    func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
        updateWindowSize()
    }

    /// Show result mode with transcribed text
    func showResultMode(text: String) {
        transcribedText = text
        showResult = true
        isRecording = false
        isTranscribing = false
        updateWindowSize()
    }

    /// Update window size when transformation state changes
    func updateWindowSizeForTransform() {
        updateWindowSize()
    }

    // MARK: - Private Methods

    private func createWindow() {
        // Calculate window size
        let panelWidth = Config.recordingPanelWidth
        let panelHeight = Config.recordingPanelHeight

        // Create borderless window
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Wrap in hosting view with observed state
        let hostingView = NSHostingView(rootView: RecordingPanelHostView(controller: self))

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true  // Allow dragging anywhere
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window = panel
    }

    /// Update window size based on current mode
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
}

/// Wrapper view that observes the controller's state
struct RecordingPanelHostView: View {
    @ObservedObject var controller: RecordingPanelController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
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
    }
}
