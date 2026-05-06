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
                if !isTranscribing {
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
            Text("RAYEE")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundColor(.white)
                .tracking(0.5)
                .padding(.leading, 20)

            Spacer()

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
        let clamped = max(0.001, min(1.0, level))
        let normalized = CGFloat(clamped)
        return 4 + normalized * 40
    }

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

    @ViewBuilder
    private var transcribingContent: some View {
        Color.clear.frame(height: 54)
    }

    @ViewBuilder
    private var resultContent: some View {
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

#Preview("Recording") {
    let monitor = AudioLevelMonitor()
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
