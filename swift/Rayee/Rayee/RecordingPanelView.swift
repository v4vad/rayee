//
//  RecordingPanelView.swift
//  Rayee
//
//  The floating panel that appears during recording.
//  Shows status, transcribed text, and transformation buttons.
//

import SwiftUI

/// The content view for the floating recording panel
struct RecordingPanelView: View {
    /// Whether currently recording (vs transcribing)
    let isRecording: Bool

    /// Whether transcription is in progress
    let isTranscribing: Bool

    /// Audio level monitor (retained for future use)
    @ObservedObject var audioLevelMonitor: AudioLevelMonitor

    /// Transcribed text to display (for result mode)
    @Binding var transcribedText: String

    /// Whether to show result mode (editable text + copy)
    let showResult: Bool

    /// Called when user clicks Done button
    var onStop: () -> Void

    /// Called when user clicks Cancel button
    var onCancel: () -> Void

    /// Called when user wants to open settings
    var onSettings: () -> Void

    /// Called when user copies text in result mode
    var onCopy: () -> Void

    /// Transformation state (nil if transformations disabled)
    var transformState: TransformationState?

    /// Whether transformations are enabled
    var transformationsEnabled: Bool

    /// Which transformations the user has enabled
    var enabledTransformations: Set<String>

    /// Called when user taps a transformation button
    var onTransform: ((TransformationType) -> Void)?

    /// Called when user accepts the transformed text
    var onUseTransformed: ((String) -> Void)?

    /// Called when user reverts to original text
    var onUseOriginal: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and settings icon
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Main content area
            mainContentView
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)

            // Bottom buttons
            if isRecording || isTranscribing || showResult {
                buttonBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: Config.recordingPanelWidth)
        .background(panelBackground)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            // Spacer to balance the settings button
            Color.clear.frame(width: 20, height: 20)

            Spacer()

            // Title
            Text("Rayee")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            // Settings button
            Button(action: onSettings) {
                Image(systemName: "gear")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var mainContentView: some View {
        if showResult {
            // Result mode: editable text with copy button
            resultView
        } else if isRecording {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Recording...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } else if isTranscribing {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            // Show transformation preview if active (loading, preview, or error)
            if let tState = transformState, tState.isActive {
                TransformationPreviewView(
                    transformState: tState,
                    onUseTransformed: { text in onUseTransformed?(text) },
                    onUseOriginal: { onUseOriginal?() }
                )
            } else {
                // Editable text area
                TextEditor(text: $transcribedText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .frame(height: 60)

                // Transformation bar (below text editor)
                if transformationsEnabled, let tState = transformState {
                    TransformationBar(
                        transformState: tState,
                        enabledTypes: enabledTransformations,
                        onTransform: { type in onTransform?(type) }
                    )
                }

                // Copy button
                copyButton
            }
        }
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                Text("Copy")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(PillButtonStyle(isProminent: true))
        .disabled(transcribedText.isEmpty)
    }

    private var buttonBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .buttonStyle(PillButtonStyle(isProminent: false))
            Spacer()
            if isRecording {
                Button("Done", action: onStop)
                    .buttonStyle(PillButtonStyle(isProminent: true))
            }
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: Config.panelCornerRadius)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

#Preview("Recording") {
    RecordingPanelView(
        isRecording: true,
        isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant(""),
        showResult: false,
        onStop: {},
        onCancel: {},
        onSettings: {},
        onCopy: {},
        transformState: nil,
        transformationsEnabled: false,
        enabledTransformations: []
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Result with Transforms") {
    RecordingPanelView(
        isRecording: false,
        isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant("Hello, this is transcribed text."),
        showResult: true,
        onStop: {},
        onCancel: {},
        onSettings: {},
        onCopy: {},
        transformState: TransformationState(),
        transformationsEnabled: true,
        enabledTransformations: Set(TransformationType.allCases.map(\.rawValue))
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}
