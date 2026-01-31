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
    /// Rolling buffer of audio levels (most recent at the end)
    @Published var levels: [Float] = []

    /// How many levels to keep in the buffer
    private let bufferSize: Int

    init(bufferSize: Int = Config.waveformBarCount) {
        self.bufferSize = bufferSize
        // Initialize with silent levels
        levels = Array(repeating: 0.01, count: bufferSize)
    }

    /// Add a new audio level reading
    /// Called frequently by AudioRecorder during recording
    func addLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.levels.append(level)

            // Keep only the most recent readings
            if self.levels.count > self.bufferSize {
                self.levels.removeFirst(self.levels.count - self.bufferSize)
            }
        }
    }

    /// Reset to silent state
    func reset() {
        levels = Array(repeating: 0.01, count: bufferSize)
    }
}
