//
//  RecordingPanelView.swift
//  Rayee
//
//  The floating panel that appears during recording.
//  Features a modern design with title, waveform, and pill-shaped buttons.
//

import SwiftUI

/// The content view for the floating recording panel
struct RecordingPanelView: View {
    /// Whether currently recording (vs transcribing)
    let isRecording: Bool

    /// Whether transcription is in progress
    let isTranscribing: Bool

    /// Audio level monitor for waveform
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
            // Recording mode: dot grid that blooms with your voice
            VStack(spacing: 8) {
                DotGridView(levels: $audioLevelMonitor.levels, mode: .listening)

                Text("Recording...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } else if isTranscribing {
            // Transcribing mode: rotating radar sweep on dot grid
            VStack(spacing: 8) {
                DotGridView(levels: .constant([]), mode: .transcribing)

                Text("Transcribing...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 8) {
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

            // Copy button
            copyButton
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        if #available(macOS 26, *) {
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                    Text("Copy")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(transcribedText.isEmpty)
        } else {
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
    }

    @ViewBuilder
    private var buttonBar: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                HStack {
                    GlassHotkeyButton("Cancel", hotkeySymbol: "⎋", action: onCancel)
                    Spacer()
                    if isRecording {
                        GlassHotkeyButton("Done", hotkeySymbol: "↵", isProminent: true, action: onStop)
                    }
                }
            }
        } else {
            HStack {
                HotkeyButton("Cancel", hotkeySymbol: "⎋", action: onCancel)
                Spacer()
                if isRecording {
                    HotkeyButton("Done", hotkeySymbol: "↵", isProminent: true, action: onStop)
                }
            }
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: Config.panelCornerRadiusGlass))
        } else {
            RoundedRectangle(cornerRadius: Config.panelCornerRadiusLegacy)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        }
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
        onCopy: {}
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Transcribing") {
    RecordingPanelView(
        isRecording: false,
        isTranscribing: true,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant(""),
        showResult: false,
        onStop: {},
        onCancel: {},
        onSettings: {},
        onCopy: {}
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}

#Preview("Result") {
    RecordingPanelView(
        isRecording: false,
        isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: .constant("Hello, this is transcribed text."),
        showResult: true,
        onStop: {},
        onCancel: {},
        onSettings: {},
        onCopy: {}
    )
    .padding()
    .background(Color.gray.opacity(0.3))
}
