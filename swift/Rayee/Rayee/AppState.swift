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
    @Published var status: AppStatus = .ready {
        didSet { lastActivity = Date() }
    }

    /// When Rayee last started or finished something; updates wait for a quiet spell after it
    private(set) var lastActivity: Date?

    /// True while a dictation is being recorded, transcribed, cleaned up or shown
    var isBusy: Bool {
        status == .recording || status == .transcribing || !cleanups.isEmpty || recorder.phase != .hidden
    }

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

    /// A Smart Dictation clean-up running (or waiting its turn) in the background
    private struct Cleanup {
        let raw: String
        let canPaste: Bool
        /// Its place in the paste line (nil when there is nowhere to paste)
        let slot: DeliveryLine.Slot?
        var task: Task<Void, Never>?
    }
    private var cleanups: [Int: Cleanup] = [:]
    private var nextCleanupID = 0
    /// The clean-up the recorder is showing ("Cleaning up"); Esc or a click skips this one
    private var shownCleanupID: Int?
    /// Clean-ups run one at a time, in the order the dictations were spoken
    private let cleanupQueue = CleanupQueue()

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

        // Forward live words to the recorder's preview
        transcriptionCoordinator.onLiveTranscript = { [weak self] transcript in
            self?.recorder.showLiveTranscript(transcript)
        }

        // Load Apple's recognizer at launch and whenever the preview language changes,
        // so the first live words of a dictation come sooner
        SettingsManager.shared.$livePreviewEnabled
            .combineLatest(SettingsManager.shared.$livePreviewLanguage)
            .sink { enabled, language in
                guard enabled else { return }
                Task { await LivePreviewPreparer.shared.warmUp(languageIdentifier: language) }
            }
            .store(in: &cancellables)

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

            let phase = RecorderRules.afterTranscription(
                text: text, didPaste: didPaste, smartDictationWillRun: smartDictationWillRun)
            if smartDictationWillRun {
                recorder.show(phase)
                let slot = transcriptionCoordinator.pendingSmartDictationSlot
                runSmartDictation(raw: text, slot: slot, canPaste: slot != nil || practiceHandler != nil)
            } else if phase == .hidden, showCleanupIndicatorIfRunning() {
                // Nothing to show for this one; an earlier clean-up is still going
            } else {
                shownCleanupID = nil
                recorder.show(phase)
            }

        case .cancelled:
            status = .ready
            if !showCleanupIndicatorIfRunning() { recorder.hide() }

        case .error(let message, let action):
            errorMessage = message
            status = .error
            shownCleanupID = nil
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
            // This runs inside the event tap, so only the decision is made here;
            // the actual work (stopping audio, pasting, hiding) runs right after.
            DispatchQueue.main.async { [weak self] in
                self?.perform(command)
            }
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
    /// Earlier clean-ups carry on in the background.
    func cancelRecording() {
        transcriptionCoordinator.cancel()
        status = .ready
        if !showCleanupIndicatorIfRunning() { recorder.hide() }
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

    /// Cleans up the transcript in the background, then pastes it (or shows it, when there's nowhere to paste).
    /// A newer dictation can start meanwhile; clean-ups run one at a time and pastes keep the spoken order.
    private func runSmartDictation(raw: String, slot: DeliveryLine.Slot?, canPaste: Bool) {
        let id = nextCleanupID
        nextCleanupID += 1
        cleanups[id] = Cleanup(raw: raw, canPaste: canPaste, slot: slot, task: nil)
        shownCleanupID = id
        let task = cleanupQueue.enqueue { [weak self] in
            // Skipped while waiting for an earlier clean-up: the skip already delivered the raw text
            guard !Task.isCancelled else { return }
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
            // Skipped while the model was finishing: the skip already delivered the raw text
            guard !Task.isCancelled else { return }
            self?.finishCleanup(id: id, cleaned: cleaned)
        }
        cleanups[id]?.task = task
    }

    private func finishCleanup(id: Int, cleaned: String?) {
        guard let cleanup = cleanups.removeValue(forKey: id) else { return }
        lastActivity = Date()
        saveSmartDictationHistory(raw: cleanup.raw, cleaned: cleaned)
        let outcome = RecorderRules.afterCleanup(raw: cleanup.raw, cleaned: cleaned, canPaste: cleanup.canPaste)
        if let text = outcome.pasteText {
            deliver(text, slot: cleanup.slot)
        } else if let slot = cleanup.slot {
            transcriptionCoordinator.deliveryLine.drop(slot)
        }
        transcribedText = cleaned ?? cleanup.raw
        // The recorder shows only the newest dictation: an older clean-up changes it only
        // when it is the one on screen and nothing newer is being recorded or transcribed.
        if shownCleanupID == id {
            shownCleanupID = nil
            // A newer recording or transcription has already replaced "Cleaning up" on the recorder
            if recorder.phase == .cleaningUp { recorder.show(outcome.phase) }
        }
    }

    /// Esc or a click during "Cleaning up": use the raw text now (in its turn in the paste line).
    /// Earlier clean-ups still running are ahead of it in the line, so they are skipped too.
    private func skipCleanup() {
        guard let shown = shownCleanupID, cleanups[shown] != nil else { return }
        for id in CleanupSkip.ids(upTo: shown, among: Array(cleanups.keys)) {
            cleanups[id]?.task?.cancel()
            finishCleanup(id: id, cleaned: nil)
        }
    }

    /// Puts "Cleaning up" back on the recorder if the clean-up it showed is still running.
    private func showCleanupIndicatorIfRunning() -> Bool {
        guard let id = shownCleanupID, cleanups[id] != nil else { return false }
        recorder.show(.cleaningUp)
        return true
    }

    /// Hands the text to onboarding's practice box, or fills its place in the paste line.
    private func deliver(_ text: String, slot: DeliveryLine.Slot?) {
        if let practiceHandler {
            practiceHandler(text)
            if let slot { transcriptionCoordinator.deliveryLine.drop(slot) }
            return
        }
        if let slot { transcriptionCoordinator.deliveryLine.fill(slot, text) }
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
