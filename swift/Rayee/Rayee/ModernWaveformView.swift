//
//  ModernWaveformView.swift
//  Rayee
//
//  A modern waveform visualization with capsule bars and gradient colors.
//  Bars grow from the center (both up and down) with smooth spring animations.
//

import SwiftUI

/// Modern waveform with capsule bars and blue-purple gradient
struct ModernWaveformView: View {
    /// Array of audio level values (0.0 to 1.0)
    @Binding var levels: [Float]

    /// Number of bars to display
    let barCount: Int

    /// Maximum height for the bars (total, split between top and bottom)
    let maxHeight: CGFloat

    init(
        levels: Binding<[Float]>,
        barCount: Int = Config.waveformBarCount,
        maxHeight: CGFloat = 50
    ) {
        self._levels = levels
        self.barCount = barCount
        self.maxHeight = maxHeight
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                ModernWaveformBar(
                    level: levelForBar(at: index),
                    maxHeight: maxHeight,
                    index: index,
                    totalBars: barCount
                )
            }
        }
    }

    /// Get the audio level for a specific bar index
    private func levelForBar(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0.02 }

        // Map bar index to levels array
        let levelIndex = min(index, levels.count - 1)
        return levels[levelIndex]
    }
}

/// Single capsule bar in the modern waveform
struct ModernWaveformBar: View {
    let level: Float
    let maxHeight: CGFloat
    let index: Int
    let totalBars: Int

    var body: some View {
        Capsule()
            .fill(barGradient)
            .frame(width: 6, height: barHeight)
            .animation(.spring(response: 0.15, dampingFraction: 0.7), value: level)
    }

    /// Height based on audio level (minimum 6px for visibility)
    private var barHeight: CGFloat {
        // Scale level with some boost for visual effect
        let normalizedLevel = min(max(CGFloat(level) * 8, 0), 1)
        return max(6, normalizedLevel * maxHeight)
    }

    /// Gradient color based on bar position (blue to purple across the waveform)
    private var barGradient: LinearGradient {
        // Calculate position in the waveform (0.0 to 1.0)
        let position = CGFloat(index) / CGFloat(max(totalBars - 1, 1))

        // Interpolate between blue and purple
        let startColor = Color(hue: 0.58, saturation: 0.7, brightness: 0.9)  // Blue
        let endColor = Color(hue: 0.75, saturation: 0.6, brightness: 0.85)    // Purple

        // Use position to shift the gradient
        return LinearGradient(
            colors: [
                startColor.opacity(0.8 + position * 0.2),
                endColor.opacity(0.6 + position * 0.4)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

#Preview("Modern Waveform") {
    VStack {
        ModernWaveformView(
            levels: .constant([0.1, 0.3, 0.5, 0.7, 0.4, 0.2, 0.6, 0.8,
                               0.5, 0.3, 0.4, 0.6, 0.3, 0.2, 0.4, 0.1])
        )
        .frame(height: 50)
    }
    .padding()
    .background(Color.black.opacity(0.1))
}
