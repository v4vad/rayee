//
//  AppState.swift
//  Rayee
//
//  Tracks the app's current state: what it's doing, transcribed text, errors, etc.
//  This is the "brain" that all UI components read from.
//
//  Note: Recording and health check logic have been extracted to:
//  - TranscriptionCoordinator: handles recording → transcription → paste
//  - HealthMonitor: handles periodic server health checks
//

import Foundation
import SwiftUI
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

    /// Controls the floating recording panel
    private let recordingPanelController = RecordingPanelController()

    /// For observing state changes
    private var cancellables = Set<AnyCancellable>()

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

    /// Copy the transcribed text to the clipboard
    func copyToClipboard() {
        guard !transcribedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcribedText, forType: .string)
    }

    /// Clear any error message
    func clearError() {
        errorMessage = nil
        if status == .error {
            status = .ready
        }
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

    /// Color for the status indicator dot
    var statusColor: Color {
        switch status {
        case .loadingModels: return .blue
        case .ready: return .green
        case .recording: return .red
        case .transcribing: return .orange
        case .error: return .red
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
                if isRecording {
                    self.status = .recording
                    // Show the floating panel
                    self.recordingPanelController.setRecording(true)
                    self.recordingPanelController.showPanel()
                } else {
                    self.recordingPanelController.setRecording(false)
                }
            }
            .store(in: &cancellables)

        // Observe transcription coordinator - transcribing state
        transcriptionCoordinator.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranscribing in
                guard let self = self else { return }
                if isTranscribing {
                    self.status = .transcribing
                    self.recordingPanelController.setTranscribing(true)
                } else {
                    self.recordingPanelController.setTranscribing(false)
                }
            }
            .store(in: &cancellables)

        // Handle transcription completion
        transcriptionCoordinator.onTranscriptionComplete = { [weak self] result in
            self?.handleTranscriptionResult(result)
        }

        // Forward audio levels to the panel's waveform
        transcriptionCoordinator.onAudioLevelUpdate = { [weak self] level in
            self?.recordingPanelController.audioLevelMonitor.addLevel(level)
        }

        // Set up panel button callbacks
        recordingPanelController.onStop = { [weak self] in
            self?.stopRecording()
        }
        recordingPanelController.onCancel = { [weak self] in
            self?.cancelRecording()
        }
        // Note: onSettings is handled in RecordingPanelHostView with @Environment
        recordingPanelController.onCopy = { [weak self] in
            self?.copyFromPanel()
        }

        // Transformation callbacks
        recordingPanelController.onTransform = { [weak self] type in
            self?.handleTransformation(type: type)
        }
        recordingPanelController.onUseTransformed = { [weak self] text in
            self?.handleUseTransformed(text: text)
        }
        recordingPanelController.onUseOriginal = { [weak self] in
            self?.handleUseOriginal()
        }

    }

    /// Handle transcription completion results
    private func handleTranscriptionResult(_ result: TranscriptionResult) {
        switch result {
        case .success(let text, let didPaste):
            transcribedText = text
            status = .ready

            // If paste was attempted but there was no valid target,
            // or auto-paste is disabled, show result in panel
            if !didPaste && !text.isEmpty {
                // Show result mode in the floating panel
                recordingPanelController.showResultMode(text: text)
            } else {
                // Paste happened successfully, hide the panel
                recordingPanelController.hidePanel()
            }

        case .cancelled:
            status = .ready
            // Hide the panel when cancelled
            recordingPanelController.hidePanel()

        case .error(let message):
            errorMessage = message
            status = .error
            // Hide the panel on error
            recordingPanelController.hidePanel()
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

        // Handle Escape key to cancel recording
        // Returns true to consume the key (prevent it from reaching other apps)
        // Returns false to let Escape work normally when not recording
        hotkeyManager.onEscapePressed = { [weak self] in
            guard let self = self else { return false }

            if self.status == .recording {
                self.cancelRecording()
                return true  // Consume the Escape key
            }
            return false  // Let Escape pass through to other apps
        }
    }

    // MARK: - Transformation Handling

    /// Handle a transformation request from the recording panel
    private func handleTransformation(type: TransformationType) {
        let text = recordingPanelController.transcribedText
        guard !text.isEmpty else { return }

        let transformState = recordingPanelController.transformState
        transformState.startTransformation(text: text, type: type)
        recordingPanelController.updateWindowSizeForTransform()

        Task { @MainActor in
            do {
                try await MLXTransformManager.shared.streamTransform(
                    text: text,
                    type: type,
                    onToken: { [weak self] token in
                        transformState.appendStreamingToken(token)
                        self?.recordingPanelController.updateWindowSizeForTransform()
                    }
                )
                // Streaming complete — finalize with accumulated text
                transformState.completeTransformation(transformedText: transformState.streamingText)
                recordingPanelController.updateWindowSizeForTransform()
            } catch {
                transformState.failTransformation(message: error.localizedDescription)
                recordingPanelController.updateWindowSizeForTransform()
            }
        }
    }

    /// Handle user accepting the transformed text
    private func handleUseTransformed(text: String) {
        recordingPanelController.transcribedText = text
        transcribedText = text
        recordingPanelController.transformState.reset()
        recordingPanelController.updateWindowSizeForTransform()
    }

    /// Handle user reverting to original text
    private func handleUseOriginal() {
        let originalText = recordingPanelController.transformState.previewOriginal
        if !originalText.isEmpty {
            recordingPanelController.transcribedText = originalText
            transcribedText = originalText
        }
        recordingPanelController.transformState.reset()
        recordingPanelController.updateWindowSizeForTransform()
    }

    /// Cancel recording without transcribing (called when user presses Escape)
    func cancelRecording() {
        transcriptionCoordinator.cancel()
        recordingPanelController.hidePanel()
        status = .ready
    }

    /// Copy text from the result panel and dismiss it
    private func copyFromPanel() {
        let text = recordingPanelController.transcribedText
        guard !text.isEmpty else { return }

        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Also update the main transcribed text
        transcribedText = text

        // Hide the panel after copying
        recordingPanelController.hidePanel()
    }
}
