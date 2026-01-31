//
//  Config.swift
//  Rayee
//
//  Centralized configuration values for the app.
//  All "magic numbers" (timeouts, retry counts, URLs) live here.
//  This makes it easy to find and change settings in one place.
//

import Foundation

/// Central configuration for Rayee
/// Group related settings together for easy discovery
enum Config {

    // MARK: - Server Connection

    /// The Python server runs on this URL
    static let serverBaseURL = "http://127.0.0.1:8765"

    // MARK: - Timeouts

    /// Timeout for regular API requests (health check, status)
    static let regularTimeout: TimeInterval = 5.0

    /// Timeout for transcription requests (recording + processing can take a while)
    static let transcriptionTimeout: TimeInterval = 120.0

    // MARK: - Health Check

    /// How often to check if the server is running (seconds)
    static let healthCheckInterval: TimeInterval = 10.0

    /// After server starts running, we check less frequently (seconds)
    static let healthCheckIntervalWhenRunning: TimeInterval = 30.0

    /// Faster health checks while waiting for server to start (seconds)
    static let healthCheckIntervalDuringStartup: TimeInterval = 2.0

    // MARK: - Startup & Retry

    /// How many times to retry connecting during startup
    static let startupRetryAttempts = 15

    /// Wait time between startup retry attempts (seconds)
    static let startupRetryDelay: TimeInterval = 1.0

    /// Maximum times to restart server after crash
    static let maxServerRestartAttempts = 3

    /// Delay before attempting server restart (seconds)
    static let serverRestartDelay: TimeInterval = 1.0

    // MARK: - Audio Recording

    /// Audio sample rate for recording (Hz) - Whisper expects 16kHz
    static let audioSampleRate: Double = 16000.0

    /// Audio level below this is considered silence
    static let silenceThreshold: Float = 0.01

    /// Maximum recording duration before auto-stop (seconds)
    static let maxRecordingDuration: TimeInterval = 60.0

    /// Default timeout before stopping (seconds) - user can override in settings
    static let defaultSilenceDuration: TimeInterval = 30.0

    /// Minimum silence duration for the settings slider (seconds)
    static let minSilenceDuration: TimeInterval = 5.0

    /// Maximum silence duration for the settings slider (seconds)
    static let maxSilenceDuration: TimeInterval = 60.0

    // MARK: - Recording Panel

    /// Width of the floating recording panel
    static let recordingPanelWidth: CGFloat = 280

    /// Height of the floating recording panel
    static let recordingPanelHeight: CGFloat = 160

    /// Number of bars in the waveform visualization
    static let waveformBarCount = 20

    // MARK: - UI Delays

    /// Delay before auto-pasting transcribed text (seconds)
    /// Gives time for the previous app to regain focus
    static let autoPasteDelay: TimeInterval = 0.1

    /// Delay before retrying hotkey registration after permission prompt (seconds)
    static let hotkeyRetryDelay: TimeInterval = 1.0
}
