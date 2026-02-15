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

    /// Corner radius for Liquid Glass panels (slightly larger for the glass look)
    static let panelCornerRadiusGlass: CGFloat = 16

    /// Corner radius for legacy material panels (pre-macOS 26)
    static let panelCornerRadiusLegacy: CGFloat = 12

    /// Width of the floating recording panel
    static let recordingPanelWidth: CGFloat = 260

    /// Height of the floating recording panel (normal mode)
    static let recordingPanelHeight: CGFloat = 155

    /// Height of the floating recording panel (with result text)
    static let recordingPanelHeightWithResult: CGFloat = 200

    /// Number of audio level readings to keep in the buffer
    static let waveformBarCount = 16

    // MARK: - Dot Grid Animation

    /// Number of columns in the dot grid
    static let dotGridColumns = 11

    /// Number of rows in the dot grid
    static let dotGridRows = 7

    /// Default dot diameter (points)
    static let dotGridDotSize: CGFloat = 6.0

    /// Maximum dot diameter when audio is loud (points)
    static let dotGridMaxDotSize: CGFloat = 8.0

    /// Height of the dot grid area
    static let dotGridHeight: CGFloat = 56.0

    /// Time for one full radar sweep rotation (seconds)
    static let dotGridSweepDuration: TimeInterval = 2.0

    /// Width of the radar sweep wedge (degrees)
    static let dotGridSweepWidth: Double = 60.0

    /// Multiplier to boost audio levels for visual effect
    static let dotGridAudioBoost: Float = 8.0

    // MARK: - UI Delays

    /// Delay before auto-pasting transcribed text (seconds)
    /// Gives time for the previous app to regain focus
    static let autoPasteDelay: TimeInterval = 0.1

    /// Delay before retrying hotkey registration after permission prompt (seconds)
    static let hotkeyRetryDelay: TimeInterval = 1.0

    // MARK: - File Upload

    /// Timeout for file upload transcription (10 minutes for long audio files)
    static let fileUploadTranscriptionTimeout: TimeInterval = 600.0

    /// Audio file types the user can select in the file picker
    static let allowedAudioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "caf"]

    /// Whether background upload transcription is enabled by default
    static let defaultBackgroundUpload = false

    // MARK: - Settings Window

    /// Width of the Settings window
    static let settingsWindowWidth: CGFloat = 650

    /// Minimum height of the Settings window
    static let settingsWindowMinHeight: CGFloat = 500

}
