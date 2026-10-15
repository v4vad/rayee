//
//  Config.swift
//  Rayee
//
//  Centralized configuration values for the app.
//  All "magic numbers" (timeouts, sizes, thresholds) live here.
//  This makes it easy to find and change settings in one place.
//

import Foundation

/// Central configuration for Rayee
/// Group related settings together for easy discovery
enum Config {

    // MARK: - Model Storage

    /// Local directory for WhisperKit model downloads.
    /// Kept under ~/.rayee (NOT ~/Documents/huggingface) so models never sync to
    /// iCloud and waste the user's iCloud storage.
    static let whisperKitDownloadBase: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".rayee").appendingPathComponent("whisperkit_models")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    // MARK: - Audio Recording

    /// Audio sample rate for recording (Hz) - Whisper expects 16kHz
    static let audioSampleRate: Double = 16000.0

    /// Audio level below this is considered silence
    static let silenceThreshold: Float = 0.01

    /// Minimum threshold floor for adaptive VAD (prevents near-zero threshold in dead-silent rooms)
    static let minSilenceThreshold: Float = 0.005

    /// Highest threshold adaptive VAD may choose. Stops speech during calibration from
    /// pushing the threshold above normal speaking level.
    static let maxAdaptiveSilenceThreshold: Float = 0.03

    /// Audio kept from just before speech is detected, so soft first sounds aren't clipped (seconds)
    static let preRollDuration: TimeInterval = 0.3

    /// Maximum recording duration before auto-stop (seconds), when the timeout switch is on
    static let maxRecordingDuration: TimeInterval = 300.0

    /// Default timeout before stopping (seconds) - user can override in settings
    static let defaultSilenceDuration: TimeInterval = 30.0

    /// Minimum silence duration for the settings slider (seconds)
    static let minSilenceDuration: TimeInterval = 5.0

    /// Maximum silence duration for the settings slider (seconds)
    static let maxSilenceDuration: TimeInterval = 60.0

    // MARK: - Recording Panel

    /// Corner radius for the floating panel
    static let panelCornerRadius: CGFloat = 12

    /// Width of the floating recording panel
    static let recordingPanelWidth: CGFloat = 400

    /// Height — Idle state
    static let recordingPanelHeight: CGFloat = 100

    /// Height — Recording state (waveform visible)
    static let recordingPanelHeightRecording: CGFloat = 164

    /// Height — Transcribing state
    static let recordingPanelHeightTranscribing: CGFloat = 108

    /// Height — Result state, format options collapsed
    static let recordingPanelHeightWithResult: CGFloat = 193

    /// Height — Result state, format options expanded
    static let recordingPanelHeightResultExpanded: CGFloat = 366

    /// Height of the panel when showing transformation preview (TransformationPreviewView)
    static let recordingPanelHeightWithTransform: CGFloat = 420

    /// Height — Error state (message + Dismiss)
    static let recordingPanelHeightError: CGFloat = 170

    /// Number of waveform bars (matches Figma design)
    static let waveformBarCount = 27

    // MARK: - UI Delays

    /// Delay before auto-pasting transcribed text (seconds)
    /// Gives time for the previous app to regain focus
    static let autoPasteDelay: TimeInterval = 0.1

    /// How long after pasting before the user's own clipboard is put back (seconds).
    /// Gives the target app time to read the pasted text first.
    static let clipboardRestoreDelay: TimeInterval = 0.5

    /// Delay before backup hotkey start attempt from AppDelegate (seconds)
    static let hotkeyBackupStartDelay: TimeInterval = 2.0

    /// How often to poll for accessibility permission when not yet granted (seconds)
    static let hotkeyPermissionPollInterval: TimeInterval = 3.0
}
