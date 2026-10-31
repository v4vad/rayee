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

    private var bodyHeight: CGFloat { controller.bodyHeight }
    private var bandHeight: CGFloat { NotchGeometry.bandHeight(controller.mode) }
    private var shapeWidth: CGFloat { NotchGeometry.shapeWidth(controller.mode) }

    private var shape: NotchShape {
        switch controller.mode {
        case .notch(let width, let height):
            return NotchShape(bandWidth: width, bandHeight: height,
                              bottomRadius: 20, topRadius: 20)
        case .capsule:
            return NotchShape(bandWidth: 0, bandHeight: 0, bottomRadius: 22, topRadius: 22)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Only redrawn when the mode or height changes (the height change is animated)
                RecorderBackground(mode: controller.mode, bodyHeight: bodyHeight)
                    .equatable()
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
            StatusRow(icon: "waveform", text: "Transcribing").transition(.opacity)
        case .cleaningUp:
            CleaningUpRow().transition(.opacity)
        case .pasted:
            pasted.transition(.opacity)
        case .result(let text):
            result(text).transition(.opacity)
        case .error(let message, let action):
            error(message, action).transition(.opacity)
        }
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
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .allowsHitTesting(false)
    }

    private var listeningRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 1, green: 0.27, blue: 0.23))
                .frame(width: 8, height: 8)
            Spacer(minLength: 0)
            Text(controller.recordingDuration >= 3 ? Self.timer(controller.recordingDuration) : "")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        // Centred on the recorder (under the camera), not in the gap between the dot and the timer
        .overlay { LevelBars(monitor: controller.audioLevelMonitor, barWidth: 2, gap: 4) }
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

/// The black shape with its fill, glow, edge and shadow. Kept apart so it is only redrawn
/// when the mode or height changes, not on every live-transcript or timer update.
private struct RecorderBackground: View, Equatable {
    let mode: RecorderLayoutMode
    let bodyHeight: CGFloat

    private var bandHeight: CGFloat { NotchGeometry.bandHeight(mode) }

    private var shape: NotchShape {
        switch mode {
        case .notch(let width, let height):
            return NotchShape(bandWidth: width, bandHeight: height,
                              bottomRadius: 20, topRadius: 20)
        case .capsule:
            return NotchShape(bandWidth: 0, bandHeight: 0, bottomRadius: 22, topRadius: 22)
        }
    }

    /// Where the body starts, as a fraction of the shape's height (0 for the capsule)
    private var bodyStart: CGFloat {
        let total = bandHeight + bodyHeight
        return total > 0 ? bandHeight / total : 0
    }

    /// Pure black inside the menu bar (so it matches the notch), lifting to a dark grey at the bottom
    private var bodyFill: LinearGradient {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: bodyStart),
            .init(color: Color(white: 0.06), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// A soft glow just inside the edge, only near the bottom
    private var glassSheen: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: bodyStart + (1 - bodyStart) * 0.5),
            .init(color: .white.opacity(0.18), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// A glass edge that is invisible at the notch and brightest along the bottom
    /// (even down the sides on purpose: a top-to-bottom ramp made the body look like a trapezium)
    private var glassEdge: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(0), location: bodyStart),
            .init(color: .white.opacity(0.08), location: min(1, bodyStart + 0.02)),
            .init(color: .white.opacity(0.08), location: bodyStart + (1 - bodyStart) * 0.6),
            .init(color: .white.opacity(0.5), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        let shape = self.shape
        return shape
            .fill(bodyFill)
            .overlay { shape.stroke(glassSheen, lineWidth: 6).blur(radius: 3).clipShape(shape) }
            .overlay { shape.stroke(glassEdge, lineWidth: 1.5).clipShape(shape) }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

/// Icon plus shimmering text for "working on it" states.
private struct StatusRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
            ShimmerText(text)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

/// The "Cleaning up" status. Watches the model manager so only this text redraws as the
/// first-time download progresses ("Downloading model… 45%").
private struct CleaningUpRow: View {
    @ObservedObject private var transformManager = MLXTransformManager.shared

    var body: some View {
        StatusRow(
            icon: "wand.and.sparkles",
            text: MLXTransformManager.preparingText(
                isLoading: transformManager.isModelLoading,
                downloadFraction: transformManager.downloadProgress) ?? "Cleaning up")
    }
}

/// Live microphone level as a row of bars. Also used by onboarding's microphone step.
struct LevelBars: View {
    @ObservedObject var monitor: AudioLevelMonitor
    var barWidth: CGFloat = 3
    /// Space between bars; defaults to the bar width
    var gap: CGFloat? = nil
    var maxHeight: CGFloat = 22

    var body: some View {
        HStack(spacing: gap ?? barWidth) {
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
