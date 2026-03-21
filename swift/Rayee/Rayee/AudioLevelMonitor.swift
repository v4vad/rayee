//
//  AudioLevelMonitor.swift
//  Rayee
//
//  Collects audio levels for the waveform visualization.
//  Maintains a rolling buffer of recent levels that the WaveformView reads from.
//

import Foundation

/// Stores audio level history for waveform visualization
class AudioLevelMonitor: ObservableObject {
    /// Ordered rolling buffer of audio levels (most recent at the end), for SwiftUI
    @Published var levels: [Float] = []

    /// How many levels to keep in the buffer
    private let bufferSize: Int

    /// Backing circular buffer — avoids O(n) removeFirst on every update
    private var buffer: [Float]
    private var writeIndex: Int = 0

    init(bufferSize: Int = Config.waveformBarCount) {
        self.bufferSize = bufferSize
        self.buffer = Array(repeating: 0.01, count: bufferSize)
        // Initialize published levels with silent values
        levels = Array(repeating: 0.01, count: bufferSize)
    }

    /// Add a new audio level reading
    /// Called frequently by AudioRecorder during recording
    func addLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Write into circular slot
            self.buffer[self.writeIndex % self.bufferSize] = level
            self.writeIndex += 1

            // Reconstruct ordered array from circular buffer
            let start = self.writeIndex % self.bufferSize
            self.levels = Array(self.buffer[start...]) + Array(self.buffer[..<start])
        }
    }

    /// Reset to silent state
    func reset() {
        buffer = Array(repeating: 0.01, count: bufferSize)
        writeIndex = 0
        levels = Array(repeating: 0.01, count: bufferSize)
    }
}
