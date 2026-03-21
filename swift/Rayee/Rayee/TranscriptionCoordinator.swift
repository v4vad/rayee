//
//  TranscriptionCoordinator.swift
//  Rayee
//
//  Coordinates the entire transcription flow:
//  1. Start recording (via AudioRecorder)
//  2. Send audio to Python server for transcription
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

/// Coordinates the recording → transcription → paste flow
class TranscriptionCoordinator: ObservableObject {
    /// Current phase of the transcription process
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false

    /// Dependencies
    private let pythonBridge: PythonBridge
    private let settings: SettingsManager
    private let historyManager: HistoryManager
    private let audioFeedback: AudioFeedback
    private let pasteManager: PasteManager

    /// Audio recorder instance (created per recording session)
    private var audioRecorder: AudioRecorder?

    /// Whether to auto-paste after current transcription
    private var pendingAutoPaste = false

    /// Callback when transcription completes
    var onTranscriptionComplete: ((TranscriptionResult) -> Void)?

    /// Callback for audio level updates (for waveform visualization)
    var onAudioLevelUpdate: ((Float) -> Void)?

    // MARK: - Initialization

    init(
        pythonBridge: PythonBridge = PythonBridge(),
        settings: SettingsManager = .shared,
        historyManager: HistoryManager = .shared,
        audioFeedback: AudioFeedback = .shared,
        pasteManager: PasteManager = .shared
    ) {
        self.pythonBridge = pythonBridge
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
        // Can't cancel transcription once audio is sent to server
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
            timeoutEnabled: settings.timeoutEnabled
        )

        // Set up callbacks
        audioRecorder?.onSpeechDetected = {
            print("[TranscriptionCoordinator] Speech detected")
        }

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
            AppLogger.log("Recording complete: \(String(format: "%.1f", recordingResult.duration))s, path: \(recordingResult.audioPath.lastPathComponent)", category: "transcription")
            transcribeAudioFile(recordingResult.audioPath)

        case .failure(let error):
            if case .noAudioRecorded = error {
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
        onTranscriptionComplete?(.error(message: error.localizedDescription))
    }

    /// Send recorded audio to Python for transcription
    private func transcribeAudioFile(_ audioPath: URL) {
        isTranscribing = true
        AppLogger.log("Sending audio to server for transcription...", category: "transcription")

        Task { @MainActor in
            do {
                let text = try await pythonBridge.transcribeFile(audioPath: audioPath)
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
                model: settings.selectedModel.rawValue
            )
        }

        // Determine if we should and can paste
        var didPaste = false
        if pendingAutoPaste && settings.autoPasteEnabled && !text.isEmpty {
            // Check if there's a valid place to paste
            if PasteTargetDetector.hasValidPasteTarget() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Config.autoPasteDelay) {
                    self.pasteManager.pasteText(text)
                }
                didPaste = true
            }
        }

        onTranscriptionComplete?(.success(text: text, didPaste: didPaste))
    }

    /// Handle transcription errors
    private func handleTranscriptionError(_ error: Error) {
        isTranscribing = false
        AppLogger.log("Transcription failed: \(error.localizedDescription)", category: "transcription")
        audioFeedback.playErrorSound()

        let message: String
        if let bridgeError = error as? PythonBridgeError {
            switch bridgeError {
            case .serverBusy:
                message = "Server is busy. Please wait."
            case .serverOffline:
                message = "Server is not running."
            case .serverStarting:
                message = "AI models are still loading. Please wait."
            default:
                message = bridgeError.localizedDescription
            }
        } else {
            message = "Transcription failed: \(error.localizedDescription)"
        }

        onTranscriptionComplete?(.error(message: message))
    }
}
