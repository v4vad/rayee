//
//  AppState.swift
//  Rayee
//
//  Tracks the app's current state: what it's doing, transcribed text, errors, etc.
//  This is the "brain" that all UI components read from.
//  Recording → transcription → paste lives in TranscriptionCoordinator.
//

import Foundation
import SwiftUI
import AppKit
import Combine

// What the app is currently doing
enum AppStatus: String {
    case loadingModels = "Loading AI models..."
    case ready = "Ready"
    case recording = "Listening..."
    case transcribing = "Transcribing..."
    case error = "Error"
}

/// Main state container - all UI components read from this
class AppState: ObservableObject {
    /// Shared singleton so both SwiftUI views and AppKit controllers use the same state
    static let shared = AppState()

    // MARK: - Published State

    /// Current status (ready, recording, etc.)
    @Published var status: AppStatus = .ready

    /// The transcribed text from your speech
    @Published var transcribedText: String = ""

    /// Error message if something goes wrong
    @Published var errorMessage: String?

    /// Whether WhisperKit model is loaded and ready
    @Published var isWhisperReady: Bool = false

    /// Whether WhisperKit model is currently loading
    @Published var isWhisperLoading: Bool = false

    // MARK: - Dependencies

    /// Handles recording → transcription → paste flow
    private let transcriptionCoordinator = TranscriptionCoordinator()

    /// Manages global hotkey listening
    let hotkeyManager = HotkeyManager.shared

    /// Shows the recorder that grows out of the notch
    private let recorder = RecorderController()

    /// For observing state changes
    private var cancellables = Set<AnyCancellable>()

    /// The Smart Dictation clean-up in progress, and what it needs if the user skips it
    private var cleanupTask: Task<Void, Never>?
    private var cleanupRaw = ""
    private var cleanupCanPaste = false

    /// When set (onboarding's "Try it" step), finished text goes here instead of being pasted
    var practiceHandler: ((String) -> Void)?

    // MARK: - Initialization

    init() {
        setupBindings()
        setupHotkey()
        startHotkeyListening()
        loadWhisperModel()
    }

    deinit {
        hotkeyManager.stop()
    }

    // MARK: - Public Methods

    /// Start recording and transcription
    /// When autoPaste is true (and settings allow), text is pasted where cursor is
    func startTranscription(autoPaste: Bool = false) {
        guard status == .ready || status == .error else { return }
        errorMessage = nil
        abandonCleanup()
        transcriptionCoordinator.startTranscription(autoPaste: autoPaste)
    }

    /// Stop recording and begin transcription (called from UI button)
    func stopRecording() {
        transcriptionCoordinator.stopRecording()
    }

    /// Load the WhisperKit model at startup
    func loadWhisperModel() {
        let modelName = SettingsManager.shared.selectedWhisperKitModel
        Task { await WhisperKitManager.shared.loadModel(modelName) }
    }

    /// Start listening for the global hotkey
    func startHotkeyListening() {
        AppLogger.log("startHotkeyListening() called", category: "hotkey")
        // Dispatch to main thread to ensure setupBindings() and setupHotkey()
        // have finished setting callbacks before start() runs
        DispatchQueue.main.async { [weak self] in
            self?.hotkeyManager.start()
        }
    }

    // MARK: - Computed Properties

    /// Icon to show in the menu bar
    var menuBarIcon: String {
        switch status {
        case .loadingModels: return "arrow.down.circle"
        case .ready: return "waveform"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "text.bubble"
        case .error: return "exclamationmark.triangle"
        }
    }

    // MARK: - Private Methods

    /// Set up Combine bindings to observe child components
    private func setupBindings() {
        // Observe WhisperKitManager — model loading state.
        // WhisperKitManager is @MainActor isolated, so its publishers must be
        // subscribed on the main actor. We schedule this after init completes.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            WhisperKitManager.shared.$isLoaded
                .sink { [weak self] loaded in
                    self?.isWhisperReady = loaded
                    if loaded && self?.status == .loadingModels {
                        self?.status = .ready
                    }
                }
                .store(in: &self.cancellables)

            WhisperKitManager.shared.$isLoading
                .sink { [weak self] loading in
                    self?.isWhisperLoading = loading
                    if loading { self?.status = .loadingModels }
                }
                .store(in: &self.cancellables)
        }

        // Observe transcription coordinator - recording state
        transcriptionCoordinator.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                // Ignore stale values: a start failure flips true then false in one turn, and a late "true" would wipe the error
                guard isRecording == self.transcriptionCoordinator.isRecording else { return }
                if isRecording {
                    self.status = .recording
                    self.recorder.show(.listening)
                }
            }
            .store(in: &cancellables)

        // Observe transcription coordinator - transcribing state
        transcriptionCoordinator.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranscribing in
                guard let self = self, isTranscribing else { return }
                self.status = .transcribing
                self.recorder.show(.transcribing)
            }
            .store(in: &cancellables)

        // Handle transcription completion
        transcriptionCoordinator.onTranscriptionComplete = { [weak self] result in
            self?.handleTranscriptionResult(result)
        }

        // Forward audio levels to the recorder's bars
        transcriptionCoordinator.onAudioLevelUpdate = { [weak self] level in
            self?.recorder.audioLevelMonitor.addLevel(level)
        }

        // Recorder clicks and buttons
        recorder.onCommand = { [weak self] command in
            self?.perform(command)
        }
        recorder.onCopy = { [weak self] text in
            self?.copyToClipboard(text)
        }
        recorder.onErrorAction = { [weak self] action in
            SystemSettingsLink.open(action.settingsURL)
            self?.recorder.hide()
        }
    }

    /// Handle transcription completion results
    private func handleTranscriptionResult(_ result: TranscriptionResult) {
        switch result {
        case .success(let text, var didPaste):
            transcribedText = text
            status = .ready

            let settings = SettingsManager.shared
            let smartDictationWillRun = SmartDictationPolicy.willRun(
                smartDictationEnabled: settings.smartDictationEnabled,
                text: text
            )
            // Onboarding's practice box counts as a paste target
            if let practiceHandler, !didPaste, !smartDictationWillRun, !text.isEmpty {
                practiceHandler(text)
                didPaste = true
            }

            recorder.show(RecorderRules.afterTranscription(
                text: text, didPaste: didPaste, smartDictationWillRun: smartDictationWillRun))
            if smartDictationWillRun {
                runSmartDictation(
                    raw: text,
                    canPaste: transcriptionCoordinator.pendingSmartDictationPaste || practiceHandler != nil)
            }

        case .cancelled:
            status = .ready
            recorder.hide()

        case .error(let message, let action):
            errorMessage = message
            status = .error
            // Explain what went wrong; Esc, ✕ or the timer closes it
            recorder.show(.error(message: message, action: action))
        }
    }

    /// Set up the global hotkey callback
    private func setupHotkey() {
        // Handle main hotkey (Option+Space by default)
        // Now works as a toggle: press to start, press again to stop and transcribe
        hotkeyManager.onHotkeyPressed = { [weak self] in
            guard let self = self else { return }
            AppLogger.log("Hotkey pressed! Current status: \(self.status.rawValue)", category: "hotkey")

            if self.status == .recording {
                // Already recording - stop and transcribe
                self.transcriptionCoordinator.stopRecording()
            } else if self.status == .ready || self.status == .error {
                // Not recording - start transcription
                self.startTranscription(autoPaste: true)
            } else {
                AppLogger.log("Hotkey ignored - status is \(self.status.rawValue)", category: "hotkey")
            }
        }

        // Esc cancels a recording, skips a clean-up, or closes a result or error.
        // Returns true to consume the key; false lets it reach the user's app.
        hotkeyManager.onEscapePressed = { [weak self] in
            guard let self = self else { return false }
            let command = RecorderRules.escape(in: self.recorder.phase)
            guard command != .none else { return false }
            self.perform(command)
            return true
        }
    }

    // MARK: - Recorder Commands

    private func perform(_ command: RecorderCommand) {
        switch command {
        case .none: break
        case .stopRecording: stopRecording()
        case .cancelRecording: cancelRecording()
        case .skipCleanup: skipCleanup()
        case .dismiss: recorder.hide()
        }
    }

    /// Cancel recording without transcribing (called when user presses Escape)
    func cancelRecording() {
        abandonCleanup()
        transcriptionCoordinator.cancel()
        recorder.hide()
        status = .ready
    }

    private func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        transcribedText = text
        recorder.hide()
    }

    // MARK: - Smart Dictation

    /// Cleans up the transcript, then pastes it (or shows it, when there's nowhere to paste).
    private func runSmartDictation(raw: String, canPaste: Bool) {
        abandonCleanup()
        cleanupRaw = raw
        cleanupCanPaste = canPaste
        cleanupTask = Task { @MainActor in
            var cleaned: String?
            do {
                // The returned text is the final result; the streamed pieces aren't shown any more.
                let finalText = try await MLXTransformManager.shared.streamTransform(
                    text: raw, type: .smartDictation, onToken: { _ in })
                let result = MLXTransformManager.cleanedOutput(finalText, input: raw)
                if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    cleaned = result
                }
            } catch is CancellationError {
                return
            } catch where Task.isCancelled {
                // Cancelled, but reported as another error type (FoundationModels has its own)
                return
            } catch {
                AppLogger.log("Smart Dictation failed: \(error.localizedDescription)", category: "mlx")
            }
            // Skipped while the model was finishing: the skip already pasted the raw text
            guard !Task.isCancelled else { return }
            self.finishCleanup(raw: raw, cleaned: cleaned, canPaste: canPaste)
        }
    }

    private func finishCleanup(raw: String, cleaned: String?, canPaste: Bool) {
        cleanupTask = nil
        saveSmartDictationHistory(raw: raw, cleaned: cleaned)
        let outcome = RecorderRules.afterCleanup(raw: raw, cleaned: cleaned, canPaste: canPaste)
        if let text = outcome.pasteText { deliver(text) }
        transcribedText = cleaned ?? raw
        recorder.show(outcome.phase)
    }

    /// Esc or a click during "Cleaning up": use the raw text now.
    private func skipCleanup() {
        guard let task = cleanupTask else { return }
        task.cancel()
        finishCleanup(raw: cleanupRaw, cleaned: nil, canPaste: cleanupCanPaste)
    }

    /// A new recording started mid clean-up: keep the raw text in History, paste nothing.
    private func abandonCleanup() {
        guard let task = cleanupTask else { return }
        task.cancel()
        cleanupTask = nil
        saveSmartDictationHistory(raw: cleanupRaw, cleaned: nil)
    }

    /// Pastes the text into the user's app, or hands it to onboarding's practice box.
    private func deliver(_ text: String) {
        if let practiceHandler {
            practiceHandler(text)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.autoPasteDelay) {
            PasteManager.shared.pasteText(text)
        }
    }

    /// Smart Dictation holds back the history save until the clean-up ends.
    /// Saves the cleaned text (with the original), or just the original if the clean-up didn't finish.
    private func saveSmartDictationHistory(raw: String, cleaned: String?) {
        let model = SettingsManager.shared.selectedWhisperKitModel
        if let cleaned {
            HistoryManager.shared.saveTranscription(
                text: cleaned,
                model: model,
                originalText: raw,
                transformations: TransformationType.smartDictation.rawValue
            )
        } else {
            HistoryManager.shared.saveTranscription(text: raw, model: model)
        }
    }
}
