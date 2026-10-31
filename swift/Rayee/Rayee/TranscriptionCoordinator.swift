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
    case error(message: String, action: RecorderErrorAction?)
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

    /// The button the recorder offers with this error, if any.
    static func action(for error: Error) -> RecorderErrorAction? {
        if let recorderError = error as? AudioRecorderError, case .noMicrophonePermission = recorderError {
            return .openMicrophoneSettings
        }
        return nil
    }
}

/// Whether Smart Dictation will clean up a transcription automatically.
/// TranscriptionCoordinator (to hold the history save) and AppState (to start the clean-up)
/// both use it, so the two can never disagree.
enum SmartDictationPolicy {
    static func willRun(smartDictationEnabled: Bool, text: String) -> Bool {
        smartDictationEnabled && !text.isEmpty
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

    /// Shows words while the user speaks (created per recording session, only if enabled)
    private var liveTranscriber: LiveTranscriber?

    /// Whether to auto-paste after current transcription
    private var pendingAutoPaste = false

    /// The place in the paste line held for the transcription that just finished, when Smart Dictation
    /// will paste its cleaned text later (nil when nothing is waiting to be pasted)
    private(set) var pendingSmartDictationSlot: DeliveryLine.Slot?

    /// Everything Rayee pastes goes through this line, so dictations land in the order they were spoken
    let deliveryLine: DeliveryLine

    /// Callback when transcription completes
    var onTranscriptionComplete: ((TranscriptionResult) -> Void)?

    /// Callback for audio level updates (for waveform visualization)
    var onAudioLevelUpdate: ((Float) -> Void)?

    /// Callback for live words while recording (for the recorder's preview)
    var onLiveTranscript: ((LiveTranscript) -> Void)?

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
        // No wait before pasting: the recorder never takes focus away from the user's app
        self.deliveryLine = DeliveryLine(paste: { text in
            await pasteManager.paste(text)
        })
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
        pendingSmartDictationSlot = nil
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
            stopLiveTranscriber()
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

        // Smart Dictation needs the text model as soon as the transcript is ready.
        // Load it while the user is still speaking so they don't wait for it afterwards.
        if settings.smartDictationEnabled {
            Task { await MLXTransformManager.shared.loadModelIfNeeded() }
        }

        // Create recorder with user's settings
        audioRecorder = AudioRecorder(
            silenceDuration: settings.silenceDuration,
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

        // Show words while the user speaks. Only a preview: the pasted text still comes from WhisperKit.
        if settings.livePreviewEnabled {
            let transcriber = LiveTranscriber(languageIdentifier: settings.livePreviewLanguage)
            liveTranscriber = transcriber
            audioRecorder?.onRawBuffer = { [weak transcriber] buffer in
                transcriber?.append(buffer)
            }
            transcriber.onTranscript = { [weak self, weak transcriber] transcript in
                guard let self, let transcriber, self.liveTranscriber === transcriber else { return }
                self.onLiveTranscript?(transcript)
            }
            transcriber.start()
        }

        // Start recording
        do {
            try audioRecorder?.startRecording()
        } catch {
            handleRecordingError(error)
        }
    }

    /// Tear down the live preview without waiting for it
    private func stopLiveTranscriber() {
        liveTranscriber?.stop()
        liveTranscriber = nil
    }

    /// Handle when recording finishes
    private func handleRecordingComplete(_ result: Result<RecordingResult, AudioRecorderError>) {
        stopLiveTranscriber()
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
        stopLiveTranscriber()
        isRecording = false
        audioRecorder = nil
        audioFeedback.playErrorSound()
        onTranscriptionComplete?(.error(
            message: UserFacingError.message(for: error), action: UserFacingError.action(for: error)))
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
        AppLogger.log("Transcription succeeded: \(text.count) characters", category: "transcription")
        audioFeedback.playStopSound()

        let smartDictationWillRun = SmartDictationPolicy.willRun(
            smartDictationEnabled: settings.smartDictationEnabled,
            text: text
        )

        // Save to history now, unless Smart Dictation is about to clean the text up.
        // In that case AppState saves the final text when the clean-up ends.
        if !text.isEmpty && !smartDictationWillRun {
            historyManager.saveTranscription(
                text: text,
                model: settings.selectedWhisperKitModel
            )
        }

        // Determine if we should and can paste
        var didPaste = false
        pendingSmartDictationSlot = nil
        let canPaste = RecorderRules.canPaste(
            requested: pendingAutoPaste,
            enabled: settings.autoPasteEnabled,
            text: text,
            hasTarget: PasteTargetDetector.hasValidPasteTarget(),
            hasAccessibility: pasteManager.hasAccessibilityPermission())
        if canPaste {
            // Take a place in the paste line now, so this text can't land before an earlier dictation's
            let slot = deliveryLine.reserve()
            if smartDictationWillRun {
                // Defer paste — smart dictation fills the place with the cleaned text
                pendingSmartDictationSlot = slot
            } else {
                deliveryLine.fill(slot, text)
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
        onTranscriptionComplete?(.error(
            message: UserFacingError.message(for: error), action: UserFacingError.action(for: error)))
    }
}
