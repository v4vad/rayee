//
//  DotGridView.swift
//  Rayee
//
//  A grid of dots that animates in two modes:
//  - Listening: dots bloom (grow + intensify color) when you speak
//  - Transcribing: a rotating radar sweep lights up dots as it passes
//

import SwiftUI

/// The two animation modes for the dot grid
enum DotGridMode {
    case listening
    case transcribing
}

/// A grid of dots with pink/magenta radial gradient that reacts to audio
struct DotGridView: View {
    /// Audio levels from the microphone (0.0 to 1.0 each)
    @Binding var levels: [Float]

    /// Which animation mode to show
    let mode: DotGridMode

    /// Radar sweep angle for transcribing mode (degrees, 0-360)
    @State private var sweepAngle: Double = 0

    /// Timer for the radar sweep rotation
    @State private var sweepTimer: Timer?

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<Config.dotGridRows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<Config.dotGridColumns, id: \.self) { col in
                        dotView(row: row, col: col)
                    }
                }
            }
        }
        .frame(height: Config.dotGridHeight)
        .onAppear {
            if mode == .transcribing {
                startSweep()
            }
        }
        .onDisappear {
            sweepTimer?.invalidate()
            sweepTimer = nil
        }
        .onChange(of: mode) { newMode in
            if newMode == .transcribing {
                startSweep()
            } else {
                sweepTimer?.invalidate()
                sweepTimer = nil
            }
        }
    }

    // MARK: - Individual Dot

    @ViewBuilder
    private func dotView(row: Int, col: Int) -> some View {
        let distance = normalizedDistance(row: row, col: col)

        Circle()
            .fill(dotColor(distance: distance, row: row, col: col))
            .frame(width: dotSize(distance: distance), height: dotSize(distance: distance))
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: audioIntensity)
            .animation(.easeInOut(duration: 0.15), value: sweepAngle)
    }

    // MARK: - Audio Intensity

    /// Overall audio intensity from 0.0 (silent) to 1.0 (loud)
    private var audioIntensity: Float {
        guard !levels.isEmpty else { return 0 }
        let avg = levels.reduce(0, +) / Float(levels.count)
        let peak = levels.max() ?? 0
        let raw = (avg * 4 + peak * 6) / 10 * Config.dotGridAudioBoost
        return min(raw, 1.0)
    }

    // MARK: - Distance from Center

    /// How far a dot is from the center of the grid (0.0 = center, 1.0 = corner)
    private func normalizedDistance(row: Int, col: Int) -> Double {
        let centerCol = Double(Config.dotGridColumns - 1) / 2.0
        let centerRow = Double(Config.dotGridRows - 1) / 2.0
        let dx = (Double(col) - centerCol) / centerCol
        let dy = (Double(row) - centerRow) / centerRow
        return min(sqrt(dx * dx + dy * dy), 1.0)
    }

    // MARK: - Dot Size

    private func dotSize(distance: Double) -> CGFloat {
        let base = Config.dotGridDotSize

        if mode == .listening {
            let maxSize = Config.dotGridMaxDotSize
            let intensity = Double(audioIntensity)
            // Center dots grow more than edge dots
            let growFactor = intensity * (1.0 - distance * 0.5)
            return base + CGFloat(growFactor) * (maxSize - base)
        }

        return base
    }

    // MARK: - Dot Color

    private func dotColor(distance: Double, row: Int, col: Int) -> Color {
        if mode == .transcribing {
            return transcribingColor(distance: distance, row: row, col: col)
        }
        return listeningColor(distance: distance)
    }

    /// Listening mode: radial gradient from deep maroon (center) to near-white (edges)
    /// Audio makes colors more vivid
    private func listeningColor(distance: Double) -> Color {
        let intensity = Double(audioIntensity)
        // How vivid colors are: base level + audio boost
        let vividness = 0.4 + intensity * 0.6

        if distance < 0.25 {
            // Center: deep maroon
            return Color(
                hue: 0.92,
                saturation: 0.85 * vividness,
                brightness: 0.4 + intensity * 0.35
            )
        } else if distance < 0.45 {
            // Ring 1: hot magenta
            return Color(
                hue: 0.92,
                saturation: 0.80 * vividness,
                brightness: 0.55 + intensity * 0.2
            )
        } else if distance < 0.65 {
            // Ring 2: hot pink
            return Color(
                hue: 0.93,
                saturation: 0.65 * vividness,
                brightness: 0.65 + intensity * 0.2
            )
        } else if distance < 0.85 {
            // Ring 3: light pink
            return Color(
                hue: 0.94,
                saturation: 0.40 * vividness,
                brightness: 0.75 + intensity * 0.15
            )
        } else {
            // Outer: near-white with a pink tint
            return Color(
                hue: 0.95,
                saturation: 0.10 * vividness,
                brightness: 0.85 + intensity * 0.1
            )
        }
    }

    /// Transcribing mode: dots light up as the radar sweep passes
    private func transcribingColor(distance: Double, row: Int, col: Int) -> Color {
        let angle = dotAngle(row: row, col: col)
        let angleDiff = angleDifference(angle, sweepAngle)
        let sweepWidth = Config.dotGridSweepWidth

        if angleDiff < sweepWidth {
            // Dot is within the sweep — light it up
            let brightness = 1.0 - (angleDiff / sweepWidth)
            let desatFactor = 0.7 // Slightly desaturated for "processing" feel

            if distance < 0.35 {
                return Color(
                    hue: 0.92,
                    saturation: 0.80 * desatFactor,
                    brightness: 0.5 + brightness * 0.4
                )
            } else if distance < 0.65 {
                return Color(
                    hue: 0.93,
                    saturation: 0.60 * desatFactor,
                    brightness: 0.55 + brightness * 0.35
                )
            } else {
                return Color(
                    hue: 0.94,
                    saturation: 0.35 * desatFactor,
                    brightness: 0.6 + brightness * 0.3
                )
            }
        }

        // Dot is outside the sweep — dim/idle
        return Color(
            hue: 0.93,
            saturation: 0.08,
            brightness: 0.75 - distance * 0.1
        )
    }

    // MARK: - Angle Helpers

    /// Angle (in degrees) from the grid center to a specific dot
    private func dotAngle(row: Int, col: Int) -> Double {
        let centerCol = Double(Config.dotGridColumns - 1) / 2.0
        let centerRow = Double(Config.dotGridRows - 1) / 2.0
        let dx = Double(col) - centerCol
        let dy = Double(row) - centerRow
        // atan2 returns radians, convert to degrees (0-360)
        let radians = atan2(dy, dx)
        let degrees = radians * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Smallest angle difference between two angles (handles wrap-around)
    private func angleDifference(_ a: Double, _ b: Double) -> Double {
        var diff = abs(a - b)
        if diff > 180 { diff = 360 - diff }
        return diff
    }

    // MARK: - Sweep Timer

    private func startSweep() {
        sweepTimer?.invalidate()
        // Update every 30ms for smooth rotation
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            let degreesPerTick = 360.0 / (Config.dotGridSweepDuration / 0.03)
            withAnimation(.linear(duration: 0.03)) {
                sweepAngle = (sweepAngle + degreesPerTick).truncatingRemainder(dividingBy: 360)
            }
        }
    }
}

// MARK: - Previews

#Preview("Listening - Silent") {
    DotGridView(
        levels: .constant(Array(repeating: Float(0.01), count: 16)),
        mode: .listening
    )
    .padding()
    .background(Color.black.opacity(0.05))
}

#Preview("Listening - Active") {
    DotGridView(
        levels: .constant([0.3, 0.5, 0.7, 0.4, 0.6, 0.8, 0.5, 0.3,
                           0.4, 0.6, 0.3, 0.2, 0.5, 0.7, 0.4, 0.3]),
        mode: .listening
    )
    .padding()
    .background(Color.black.opacity(0.05))
}

#Preview("Transcribing") {
    DotGridView(
        levels: .constant([]),
        mode: .transcribing
    )
    .padding()
    .background(Color.black.opacity(0.05))
}
