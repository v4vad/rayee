//
//  RecorderView.swift
//  Rayee
//
//  The recorder's black shape and what it shows in each state.
//  Spec: docs/superpowers/specs/2026-10-17-design-refresh-design.md §1
//

import SwiftUI

struct RecorderView: View {
    @ObservedObject var controller: RecorderController
    /// Watched so "Cleaning up" can say "Downloading model… 45%" the first time
    @ObservedObject private var transformManager = MLXTransformManager.shared

    private var bodyHeight: CGFloat { controller.bodyHeight }
    private var bandHeight: CGFloat { NotchGeometry.bandHeight(controller.mode) }
    private var shapeWidth: CGFloat { NotchGeometry.shapeWidth(controller.mode) }

    private var isCapsule: Bool {
        if case .capsule = controller.mode { return true }
        return false
    }

    private var shape: NotchShape {
        switch controller.mode {
        case .notch(let width, let height):
            return NotchShape(bandWidth: width, bandHeight: height,
                              bottomRadius: bodyHeight > 0 ? 22 : 14, topRadius: 6)
        case .capsule:
            return NotchShape(bandWidth: 0, bandHeight: 0, bottomRadius: 22, topRadius: 22)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                shape
                    .fill(Color.black)
                    .shadow(color: .black.opacity(isCapsule ? 0.35 : 0), radius: 12, y: 4)
                content
                    .frame(width: shapeWidth, height: bodyHeight)
                    .clipped()
            }
            .frame(width: shapeWidth, height: bandHeight + bodyHeight)
            .contentShape(shape)
            .onTapGesture { controller.onCommand?(RecorderRules.click(in: controller.phase)) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .hidden:
            Color.clear
        case .listening:
            listening.transition(.opacity)
        case .transcribing:
            statusRow(icon: "waveform", text: "Transcribing").transition(.opacity)
        case .cleaningUp:
            statusRow(icon: "wand.and.sparkles", text: cleaningText).transition(.opacity)
        case .pasted:
            pasted.transition(.opacity)
        case .result(let text):
            result(text).transition(.opacity)
        case .error(let message, let action):
            error(message, action).transition(.opacity)
        }
    }

    private var cleaningText: String {
        MLXTransformManager.preparingText(
            isLoading: transformManager.isModelLoading,
            downloadFraction: transformManager.downloadProgress) ?? "Cleaning up"
    }

    private var listening: some View {
        VStack(spacing: 0) {
            listeningRow
                .frame(height: RecorderLayout.compactHeight)
            if !controller.liveTranscript.isEmpty {
                liveText
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The words heard so far: settled words bright, the still-changing end dimmer.
    private var liveText: some View {
        let tail = controller.liveTranscript.visibleTail(
            maxCharacters: RecorderLayout.charsPerLine * RecorderLayout.maxLiveLines)
        return (Text(tail.settled).foregroundStyle(.white.opacity(0.9))
                + Text(tail.draft).foregroundStyle(.white.opacity(0.45)))
            .font(.system(size: 13))
            .lineLimit(RecorderLayout.maxLiveLines)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .allowsHitTesting(false)
    }

    private var listeningRow: some View {
        HStack(spacing: 12) {
            PulsingDot()
            Spacer(minLength: 0)
            LevelBars(monitor: controller.audioLevelMonitor)
            Spacer(minLength: 0)
            Text(controller.recordingDuration >= 3 ? Self.timer(controller.recordingDuration) : "")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 18)
    }

    private func statusRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
            ShimmerText(text)
        }
        .foregroundStyle(.white.opacity(0.85))
    }

    private var pasted: some View {
        HStack(spacing: 8) {
            DrawnCheckmark()
                .frame(width: 13, height: 11)
            Text("Pasted")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
    }

    private func result(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: RecorderLayout.lineHeight
                   * CGFloat(RecorderLayout.estimatedLines(text, max: RecorderLayout.maxResultLines)))
            HStack {
                Button("Copy") { controller.onCopy?(text) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                Spacer()
                Button { controller.onCommand?(.dismiss) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Close")
            }
            .frame(height: 32)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 12, trailing: 18))
    }

    private func error(_ message: String, _ action: RecorderErrorAction?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(RecorderLayout.maxErrorLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                HStack {
                    Button(action.label) { controller.onErrorAction?(action) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    Spacer()
                }
                .frame(height: 32)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: action == nil ? 16 : 12, trailing: 18))
    }

    private static func timer(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

// MARK: - Pieces

/// Live microphone level as a row of bars. Also used by onboarding's microphone step.
struct LevelBars: View {
    @ObservedObject var monitor: AudioLevelMonitor
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: barWidth) {
            ForEach(Array(monitor.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: barWidth, height: height(for: level))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: monitor.levels)
    }

    private func height(for level: Float) -> CGFloat {
        // Raw mic RMS is about 0.001–0.15; amplify so normal speech fills the range,
        // and curve it so quiet sounds still show.
        let amplified = min(1.0, level * 7.0)
        return 3 + pow(CGFloat(amplified), 0.65) * (maxHeight - 3)
    }
}

private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Color(red: 1, green: 0.27, blue: 0.23))
            .frame(width: 8, height: 8)
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dimmed = true }
            }
    }
}

/// Text with a soft highlight sweeping across it, for "working on it" states.
private struct ShimmerText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    init(_ text: String) { self.text = text }

    private let font = Font.system(size: 13, weight: .medium)

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.white.opacity(0.6))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: (sweep * 1.6 - 0.6) * geo.size.width)
                }
                .mask(Text(text).font(font))
                .opacity(reduceMotion ? 0 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = 1 }
            }
    }
}

/// A checkmark that draws itself, like Apple Pay's.
private struct DrawnCheckmark: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .onAppear { withAnimation(.easeOut(duration: 0.25)) { progress = 1 } }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
