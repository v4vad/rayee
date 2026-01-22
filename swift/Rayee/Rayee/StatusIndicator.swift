//
//  StatusIndicator.swift
//  Rayee
//
//  A small colored dot with status text.
//  Shows green for ready, red (pulsing) for recording, orange for transcribing.
//

import SwiftUI

struct StatusIndicator: View {
    let status: AppStatus
    let color: Color

    // Tracks the pulsing animation for recording state
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            // Colored status dot
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                // Add pulsing animation when recording
                .scaleEffect(status == .recording && isPulsing ? 1.3 : 1.0)
                .opacity(status == .recording && isPulsing ? 0.7 : 1.0)
                .animation(
                    status == .recording
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

            // Status text
            Text(status.rawValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .onAppear {
            // Start pulsing animation when view appears
            if status == .recording {
                isPulsing = true
            }
        }
        .onChange(of: status) { newStatus in
            // Update pulsing based on status changes
            isPulsing = newStatus == .recording
        }
    }
}

// Preview for Xcode's canvas
#Preview {
    VStack(spacing: 20) {
        StatusIndicator(status: .ready, color: .green)
        StatusIndicator(status: .recording, color: .red)
        StatusIndicator(status: .transcribing, color: .orange)
        StatusIndicator(status: .error, color: .red)
    }
    .padding()
}
