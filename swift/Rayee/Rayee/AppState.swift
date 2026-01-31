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
    case startingServer = "Starting server..."
    case downloadingModels = "Downloading AI models..."
    case ready = "Ready"
    case recording = "Listening..."
    case transcribing = "Transcribing..."
    case error = "Error"
}

/// Main state container - all UI components read from this
class AppState: ObservableObject {
    // MARK: - Published State

    /// Current status (ready, recording, etc.)
    @Published var status: AppStatus = .ready

    /// The transcribed text from your speech
    @Published var transcribedText: String = ""

    /// Error message if something goes wrong
    @Published var errorMessage: String?

    /// Whether the Python server is reachable (from HealthMonitor)
    @Published var isServerOnline: Bool = false

    // MARK: - Dependencies

    /// Handles recording → transcription → paste flow
    private let transcriptionCoordinator = TranscriptionCoordinator()

    /// Monitors server health periodically
    private let healthMonitor = HealthMonitor.shared

    /// Manages global hotkey listening
    let hotkeyManager = HotkeyManager.shared

    /// Manages the bundled Python server
    let serverManager = ServerManager.shared

    /// Controls the floating recording panel
    private let recordingPanelController = RecordingPanelController()

    /// For observing state changes
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    // Track if we've ever been fully ready - prevents status flickering after initial startup
    private var hasBeenReady: Bool = false

    init() {
        setupBindings()
        setupHotkey()
        healthMonitor.start()
    }

    deinit {
        hotkeyManager.stop()
        healthMonitor.stop()
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

    /// Start listening for the global hotkey
    func startHotkeyListening() {
        if hotkeyManager.hasAccessibilityPermissionSilent() {
            hotkeyManager.start()
        } else {
            _ = hotkeyManager.checkAccessibilityPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.hotkeyRetryDelay) { [weak self] in
                self?.hotkeyManager.start()
            }
        }
    }

    // MARK: - Computed Properties

    /// Icon to show in the menu bar
    var menuBarIcon: String {
        switch status {
        case .startingServer: return "ellipsis.circle"
        case .downloadingModels: return "arrow.down.circle"
        case .ready: return "waveform"
        case .recording: return "waveform.circle.fill"
        case .transcribing: return "text.bubble"
        case .error: return "exclamationmark.triangle"
        }
    }

    /// Color for the status indicator dot
    var statusColor: Color {
        switch status {
        case .startingServer: return .orange
        case .downloadingModels: return .blue
        case .ready: return .green
        case .recording: return .red
        case .transcribing: return .orange
        case .error: return .red
        }
    }

    // MARK: - Private Methods

    /// Set up Combine bindings to observe child components
    private func setupBindings() {
        // Observe health monitor - when server comes online, ensure we're ready
        healthMonitor.$isServerOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isOnline in
                guard let self = self else { return }
                self.isServerOnline = isOnline
                // If server is online and we're in a waiting state, transition to ready
                if isOnline && (self.status == .startingServer || self.status == .downloadingModels) {
                    self.status = .ready
                }
            }
            .store(in: &cancellables)

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

        // Observe server manager state
        serverManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverState in
                self?.handleServerStateChange(serverState)
            }
            .store(in: &cancellables)
    }

    /// Handle transcription completion results
    private func handleTranscriptionResult(_ result: TranscriptionResult) {
        switch result {
        case .success(let text):
            transcribedText = text
            status = .ready
            // Hide the panel after successful transcription
            recordingPanelController.hidePanel()

        case .cancelled:
            status = .ready
            // Hide the panel when cancelled
            recordingPanelController.hidePanel()

        case .error(let message):
            errorMessage = message
            status = .error
            // Hide the panel on error
            recordingPanelController.hidePanel()
            if message.contains("not running") {
                isServerOnline = false
            }
        }
    }

    /// Handle changes to the server manager's state
    private func handleServerStateChange(_ serverState: ServerManager.ServerState) {
        switch serverState {
        case .starting:
            // Show "Starting server..." only during initial startup
            // Once we've been ready, don't flip back (prevents flickering)
            if !hasBeenReady && (status == .ready || status == .error) {
                status = .startingServer
            }
        case .downloadingModels:
            // Show "Downloading AI models..." only during initial startup
            if !hasBeenReady && (status == .startingServer || status == .ready) {
                status = .downloadingModels
            }
        case .running:
            // Server is ready - update status if we were waiting for it
            if status == .startingServer || status == .downloadingModels {
                status = .ready
            }
            // Mark that we've successfully started once
            hasBeenReady = true
            isServerOnline = true
        case .failed:
            // Server failed - show error
            status = .error
            errorMessage = serverManager.errorMessage ?? "Server failed to start"
            isServerOnline = false
        case .notStarted, .stopped:
            break
        }
    }

    /// Set up the global hotkey callback
    private func setupHotkey() {
        // Handle main hotkey (Option+Space by default)
        // Now works as a toggle: press to start, press again to stop and transcribe
        hotkeyManager.onHotkeyPressed = { [weak self] in
            guard let self = self else { return }

            if self.status == .recording {
                // Already recording - stop and transcribe
                self.transcriptionCoordinator.stopRecording()
            } else if self.status == .ready || self.status == .error {
                // Not recording - start transcription
                self.startTranscription(autoPaste: true)
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

    /// Cancel recording without transcribing (called when user presses Escape)
    func cancelRecording() {
        transcriptionCoordinator.cancel()
        recordingPanelController.hidePanel()
        status = .ready
    }
}
