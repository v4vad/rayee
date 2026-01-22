//
//  AudioFeedback.swift
//  Rayee
//
//  Handles audio feedback sounds for recording start/stop.
//  Uses macOS built-in system sounds for a native feel.
//

import AppKit

// Manages audio feedback sounds
// Plays different sounds when recording starts and stops to provide audible confirmation
class AudioFeedback {
    // Singleton instance - one shared audio feedback manager for the whole app
    static let shared = AudioFeedback()

    // Reference to settings to check if sounds are enabled
    private let settings = SettingsManager.shared

    // System sounds we use
    // These are built into macOS, so no need to bundle audio files
    private let startSound = NSSound(named: "Tink")      // Soft "tick" for start
    private let stopSound = NSSound(named: "Pop")        // "Pop" for completion

    private init() {
        // Sounds are loaded from system - no setup needed
    }

    // MARK: - Public Methods

    /// Play the sound when recording starts
    /// Only plays if sounds are enabled in settings
    func playStartSound() {
        guard settings.soundsEnabled else { return }
        startSound?.play()
    }

    /// Play the sound when transcription completes
    /// Only plays if sounds are enabled in settings
    func playStopSound() {
        guard settings.soundsEnabled else { return }
        stopSound?.play()
    }

    /// Play an error sound when something goes wrong
    /// Only plays if sounds are enabled in settings
    func playErrorSound() {
        guard settings.soundsEnabled else { return }
        // Use the system "Basso" sound for errors - it's a deeper, alert-like sound
        NSSound(named: "Basso")?.play()
    }
}
