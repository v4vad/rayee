//
//  TranscriptionCoordinator.swift
//  Rayee
//
//  Coordinates the entire transcription flow:
//  1. Start recording (via AudioRecorder)
//  2. Transcribe the audio on-device with WhisperKit
//  3. Save to history and auto-paste if enabled
//
//  This keeps AppState simple - it just observes the coordinator's state.
//

import Foundation
import Combine

/// Result of a transcription attempt
enum TranscriptionResult {
    case success(text: String, didPaste: Bool)  // didPaste indicates if text was pasted
    case cancelled           // Recording stopped with no speech
    case error(message: String)
}

/// Turns internal errors into short, plain-language messages for the recording panel.
enum UserFacingError {
    static func message(for error: Error) -> String {
        if let recorderError = error as? AudioRecorderError {
            switch recorderError {
            case .noMicrophonePermission:
                return "Rayee can't use the microphone. Allow it in System Settings → Privacy & Security → Microphone, then try again."
            case .engineStartFailed:
                return "Couldn't start the microphone. Check that one is connected and not in use by another app."
            case .noAudioRecorded:
                return "Rayee didn't hear anything. Check your microphone and try again."
            }
        }
        if let whisperError = error as? WhisperKitError, case .modelNotLoaded = whisperError {
            return "The speech model is still loading. Try again in a few seconds."
        }
        return "Transcription failed: \(error.localizedDescription)"
    }
}

/// Coordinates the recording → transcription → paste flow
class TranscriptionCoordinator: ObservableObject {
    /// Current phase of the transcription process
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false

    /// Dependencies
    private let settings: SettingsManager
    private let historyManager: HistoryManager
    private let audioFeedback: AudioFeedback
    private let pasteManager: PasteManager

    /// Audio recorder instance (created per recording session)
    private var audioRecorder: AudioRecorder?

    /// Whether to auto-paste after current transcription
    private var pendingAutoPaste = false

    /// Whether smart dictation should paste the transformed result (set when auto-paste is deferred)
    var pendingSmartDictationPaste = false

    /// Callback when transcription completes
    var onTranscriptionComplete: ((TranscriptionResult) -> Void)?

    /// Callback for audio level updates (for waveform visualization)
    var onAudioLevelUpdate: ((Float) -> Void)?

    // MARK: - Initialization

    init(
        settings: SettingsManager = .shared,
        historyManager: HistoryManager = .shared,
        audioFeedback: AudioFeedback = .shared,
        pasteManager: PasteManager = .shared
    ) {
        self.settings = settings
        self.historyManager = historyManager
        self.audioFeedback = audioFeedback
        self.pasteManager = pasteManager
    }

    // MARK: - Public Methods

    /// Start the transcription flow
    /// - Parameter autoPaste: If true (and enabled in settings), text is pasted automatically
    func startTranscription(autoPaste: Bool = false) {
        guard !isRecording && !isTranscribing else {
            print("[TranscriptionCoordinator] Already in progress")
            return
        }

        pendingAutoPaste = autoPaste
        pendingSmartDictationPaste = false
        startRecording()
    }

    /// Stop recording and send audio for transcription
    func stopRecording() {
        if isRecording {
            audioRecorder?.stopRecording()
        }
    }

    /// Cancel recording without transcribing (e.g., user pressed Escape)
    func cancel() {
        if isRecording {
            audioRecorder?.cancelRecording()
            audioRecorder = nil
            isRecording = false
            audioFeedback.playErrorSound()
        }
        // A transcription already in progress runs to completion
    }

    // MARK: - Private Methods

    /// Start recording audio
    private func startRecording() {
        Task { @MainActor in
            // Request microphone permission if needed
            let hasPermission = await AudioRecorder.requestMicrophonePermission()
            if !hasPermission {
                // Permission might show denied but still work - try anyway
                print("[TranscriptionCoordinator] Permission check returned false, attempting recording...")
            }

            self.beginRecordingSession()
        }
    }

    /// Actually start the audio recording session
    private func beginRecordingSession() {
        isRecording = true
        audioFeedback.playStartSound()

        // Create recorder with user's settings
        audioRecorder = AudioRecorder(
            silenceDuration: settings.silenceDuration,
            timeoutEnabled: settings.timeoutEnabled,
            adaptiveVADEnabled: settings.adaptiveVADEnabled
        )

        // Set up callbacks
        audioRecorder?.onRecordingComplete = { [weak self] result in
            self?.handleRecordingComplete(result)
        }

        // Forward audio levels to the UI for waveform visualization
        audioRecorder?.onAudioLevel = { [weak self] level in
            self?.onAudioLevelUpdate?(level)
        }

        // Start recording
        do {
            try audioRecorder?.startRecording()
        } catch {
            handleRecordingError(error)
        }
    }

    /// Handle when recording finishes
    private func handleRecordingComplete(_ result: Result<RecordingResult, AudioRecorderError>) {
        audioRecorder = nil
        isRecording = false

        switch result {
        case .success(let recordingResult):
            AppLogger.log("Recording complete: \(String(format: "%.1f", recordingResult.duration))s", category: "transcription")
            transcribeRecording(recordingResult)

        case .failure(let error):
            if case .noAudioRecorded = error {
                // A denied microphone records pure silence. Say so instead of silently closing.
                if !AudioRecorder.hasMicrophonePermission() {
                    AppLogger.log("No speech heard and microphone permission is missing", category: "transcription")
                    handleRecordingError(AudioRecorderError.noMicrophonePermission)
                    return
                }
                AppLogger.log("Recording ended with no speech detected", category: "transcription")
                audioFeedback.playStopSound()
                onTranscriptionComplete?(.cancelled)
            } else {
                AppLogger.log("Recording failed: \(error.localizedDescription)", category: "transcription")
                handleRecordingError(error)
            }
        }
    }

    /// Handle recording errors
    private func handleRecordingError(_ error: Error) {
        isRecording = false
        audioRecorder = nil
        audioFeedback.playErrorSound()
        onTranscriptionComplete?(.error(message: UserFacingError.message(for: error)))
    }

    /// Transcribe recording using WhisperKit (on-device)
    private func transcribeRecording(_ result: RecordingResult) {
        isTranscribing = true
        AppLogger.log("Transcribing audio via WhisperKit...", category: "transcription")

        Task { @MainActor in
            do {
                let vocabulary = settings.vocabularyList
                let text = try await WhisperKitManager.shared.transcribe(
                    audioBuffer: result.audioData,
                    vocabulary: vocabulary
                )
                self.handleTranscriptionSuccess(text)
            } catch {
                self.handleTranscriptionError(error)
            }
        }
    }

    /// Handle successful transcription
    private func handleTranscriptionSuccess(_ text: String) {
        isTranscribing = false
        AppLogger.log("Transcription succeeded: \(text.prefix(80))...", category: "transcription")
        audioFeedback.playStopSound()

        // Save to history if we got text
        if !text.isEmpty {
            historyManager.saveTranscription(
                text: text,
                model: settings.selectedWhisperKitModel
            )
        }

        // Determine if we should and can paste
        var didPaste = false
        pendingSmartDictationPaste = false
        if pendingAutoPaste && settings.autoPasteEnabled && !text.isEmpty {
            if PasteTargetDetector.hasValidPasteTarget() {
                if settings.smartDictationEnabled && settings.transformationsEnabled {
                    // Defer paste — smart dictation will paste the transformed result
                    pendingSmartDictationPaste = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Config.autoPasteDelay) {
                        self.pasteManager.pasteText(text)
                    }
                    didPaste = true
                }
            }
        }

        onTranscriptionComplete?(.success(text: text, didPaste: didPaste))
    }

    /// Handle transcription errors
    private func handleTranscriptionError(_ error: Error) {
        isTranscribing = false
        AppLogger.log("Transcription failed: \(error.localizedDescription)", category: "transcription")
        audioFeedback.playErrorSound()
        onTranscriptionComplete?(.error(message: UserFacingError.message(for: error)))
    }
}
