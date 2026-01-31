//
//  TranscribingIndicator.swift
//  Rayee
//
//  An animated indicator shown during transcription.
//  Displays three bouncing dots with "Transcribing..." text.
//

import SwiftUI

/// Bouncing dots animation for transcription state
struct TranscribingIndicator: View {
    @State private var animatingDot = 0

    var body: some View {
        VStack(spacing: 12) {
            // Three bouncing dots
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(dotGradient)
                        .frame(width: 10, height: 10)
                        .offset(y: animatingDot == index ? -8 : 0)
                }
            }

            // Text label
            Text("Transcribing...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
        .onAppear {
            startAnimation()
        }
    }

    /// Gradient for the dots
    private var dotGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 0.58, saturation: 0.7, brightness: 0.9),  // Blue
                Color(hue: 0.75, saturation: 0.6, brightness: 0.85)  // Purple
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Start the bouncing animation
    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                animatingDot = (animatingDot + 1) % 3
            }
        }
    }
}

#Preview {
    TranscribingIndicator()
        .frame(width: 200, height: 80)
        .background(Color.black.opacity(0.05))
}
