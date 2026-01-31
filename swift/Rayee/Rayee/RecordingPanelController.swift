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

    /// Transcribed text to display
    @Published var transcribedText = ""

    /// Callbacks
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Public Methods

    /// Show the recording panel centered on screen
    func showPanel() {
        if window == nil {
            createWindow()
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)

        // Ensure it's above all other windows
        window?.level = .floating
    }

    /// Hide the recording panel
    func hidePanel() {
        window?.orderOut(nil)
    }

    /// Update recording state
    func setRecording(_ recording: Bool) {
        isRecording = recording
        if recording {
            audioLevelMonitor.reset()
        }
    }

    /// Update transcribing state
    func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
    }

    /// Update transcribed text
    func setTranscribedText(_ text: String) {
        transcribedText = text
    }

    // MARK: - Private Methods

    private func createWindow() {
        // Create the panel content view
        let contentView = RecordingPanelView(
            isRecording: isRecording,
            isTranscribing: isTranscribing,
            audioLevelMonitor: audioLevelMonitor,
            transcribedText: transcribedText,
            onStop: { [weak self] in
                self?.onStop?()
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )

        // Wrap in hosting view with observed state
        let hostingView = NSHostingView(rootView: RecordingPanelHostView(controller: self))

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

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true  // Allow dragging anywhere
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window = panel
    }
}

/// Wrapper view that observes the controller's state
struct RecordingPanelHostView: View {
    @ObservedObject var controller: RecordingPanelController

    var body: some View {
        RecordingPanelView(
            isRecording: controller.isRecording,
            isTranscribing: controller.isTranscribing,
            audioLevelMonitor: controller.audioLevelMonitor,
            transcribedText: controller.transcribedText,
            onStop: {
                controller.onStop?()
            },
            onCancel: {
                controller.onCancel?()
            }
        )
    }
}
