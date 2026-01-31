//
//  WaveformView.swift
//  Rayee
//
//  Animated waveform visualization showing audio levels.
//  Displays a row of vertical bars that grow/shrink based on sound input.
//

import SwiftUI

/// A row of animated bars that visualize audio levels
struct WaveformView: View {
    /// Array of audio level values (0.0 to 1.0)
    @Binding var levels: [Float]

    /// Number of bars to display
    let barCount: Int

    /// Maximum height for the bars
    let maxHeight: CGFloat

    init(levels: Binding<[Float]>, barCount: Int = Config.waveformBarCount, maxHeight: CGFloat = 40) {
        self._levels = levels
        self.barCount = barCount
        self.maxHeight = maxHeight
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    level: levelForBar(at: index),
                    maxHeight: maxHeight
                )
            }
        }
    }

    /// Get the audio level for a specific bar index
    private func levelForBar(at index: Int) -> Float {
        guard !levels.isEmpty else { return 0.01 }

        // Map bar index to levels array
        let levelIndex = min(index, levels.count - 1)
        return levels[levelIndex]
    }
}

/// Single bar in the waveform
struct WaveformBar: View {
    let level: Float
    let maxHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor)
            .frame(width: 8, height: barHeight)
            .animation(.easeOut(duration: 0.1), value: level)
    }

    /// Height based on audio level (minimum 4px for visibility)
    private var barHeight: CGFloat {
        let normalizedLevel = min(max(CGFloat(level) * 10, 0), 1)  // Scale up and clamp
        return max(4, normalizedLevel * maxHeight)
    }

    /// Color changes based on level
    private var barColor: Color {
        if level > 0.1 {
            return .red
        } else if level > 0.03 {
            return .orange
        } else {
            return .green
        }
    }
}

#Preview {
    WaveformView(
        levels: .constant([0.1, 0.3, 0.5, 0.2, 0.1, 0.4, 0.6, 0.3, 0.2, 0.1,
                          0.05, 0.15, 0.25, 0.35, 0.2, 0.1, 0.3, 0.4, 0.2, 0.1])
    )
    .padding()
    .background(.black)
}
