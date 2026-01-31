//
//  RecordingPanelView.swift
//  Rayee
//
//  The floating panel that appears during recording.
//  Shows recording status, waveform visualization, and control buttons.
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

    /// Transcribed text to display (for direct input mode)
    let transcribedText: String

    /// Called when user clicks Stop button
    var onStop: () -> Void

    /// Called when user clicks Cancel button
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            statusView

            // Waveform visualization (only during recording)
            if isRecording {
                WaveformView(levels: $audioLevelMonitor.levels)
                    .frame(height: 40)
            }

            // Transcribed text (when available)
            if !transcribedText.isEmpty && !isRecording && !isTranscribing {
                Text(transcribedText)
                    .font(.body)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            // Control buttons
            if isRecording || isTranscribing {
                controlButtons
            }
        }
        .padding(16)
        .frame(width: Config.recordingPanelWidth)
        .background(panelBackground)
    }

    // MARK: - Subviews

    private var statusView: some View {
        HStack(spacing: 8) {
            // Animated recording dot
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseAnimation ? 1.0 : 0.3)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
                    .onAppear { pulseAnimation = true }
            } else if isTranscribing {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Text(statusText)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Cancel button
            Button(action: onCancel) {
                Label("Cancel", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            // Stop button (only during recording)
            if isRecording {
                Button(action: onStop) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }

    // MARK: - State

    @State private var pulseAnimation = false

    // MARK: - Computed Properties

    private var statusText: String {
        if isRecording {
            return "Recording..."
        } else if isTranscribing {
            return "Transcribing..."
        } else {
            return "Done"
        }
    }
}

#Preview("Recording") {
    RecordingPanelView(
        isRecording: true,
        isTranscribing: false,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: "",
        onStop: {},
        onCancel: {}
    )
    .background(.gray)
}

#Preview("Transcribing") {
    RecordingPanelView(
        isRecording: false,
        isTranscribing: true,
        audioLevelMonitor: AudioLevelMonitor(),
        transcribedText: "",
        onStop: {},
        onCancel: {}
    )
    .background(.gray)
}
