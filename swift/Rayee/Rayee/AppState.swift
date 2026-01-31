//
//  AppState.swift
//  Rayee
//
//  Tracks the app's current state: what it's doing, transcribed text, errors, etc.
//  This is the "brain" that all UI components read from.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation

// What the app is currently doing
enum AppStatus: String {
    case startingServer = "Starting server..."  // Python server is starting up
    case downloadingModels = "Downloading AI models..."  // First-time model download
    case ready = "Ready"              // Waiting for you to start recording
    case recording = "Listening..."   // Microphone active, listening to you
    case transcribing = "Transcribing..."  // Converting speech to text
    case error = "Error"              // Something went wrong
}

// Main state container - all UI components read from this
class AppState: ObservableObject {
    // @Published means: whenever this value changes, update the UI automatically

    // Current status (ready, recording, etc.)
    @Published var status: AppStatus = .ready

    // The transcribed text from your speech
    @Published var transcribedText: String = ""

    // Error message if something goes wrong
    @Published var errorMessage: String?

    // Whether the Python server is reachable
    @Published var isServerOnline: Bool = false

    // For communicating with the Python server
    let pythonBridge = PythonBridge()

    // Managers for hotkey and paste functionality
    let hotkeyManager = HotkeyManager.shared
    let pasteManager = PasteManager.shared
    let settings = SettingsManager.shared
    let historyManager = HistoryManager.shared
    let audioFeedback = AudioFeedback.shared

    // Timer for periodic health checks
    private var healthCheckTimer: Timer?

    // For observing server manager state changes
    private var cancellables = Set<AnyCancellable>()

    // The server manager (only used in production builds with bundled server)
    let serverManager = ServerManager.shared

    // Audio recorder for Swift-side recording (fixes microphone permission in bundled app)
    private var audioRecorder: AudioRecorder?

    // Whether we should auto-paste after current transcription completes
    private var pendingAutoPaste: Bool = false

    init() {
        // Observe server manager state changes
        serverManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] serverState in
                self?.handleServerStateChange(serverState)
            }
            .store(in: &cancellables)

        // Start checking if the server is online every 10 seconds
        startHealthChecks()

        // Set up the global hotkey to trigger transcription
        setupHotkey()
    }

    deinit {
        healthCheckTimer?.invalidate()
        hotkeyManager.stop()
    }

    // MARK: - Public Methods

    /// Start recording and transcription
    /// When autoPaste is true (and settings allow it), text is automatically pasted where cursor is
    func startTranscription(autoPaste: Bool = false) {
        // Don't start if already doing something
        guard status == .ready || status == .error else { return }

        // Clear previous error
        errorMessage = nil
        pendingAutoPaste = autoPaste

        // Request microphone permission if needed
        Task { @MainActor in
            let hasPermission = await AudioRecorder.requestMicrophonePermission()
            if !hasPermission {
                // Permission check says denied, but let's try anyway
                // The audio engine will fail with a clear error if truly no permission
                print("[AppState] Permission check returned false, attempting recording anyway...")
            }

            // Start recording with Swift AudioRecorder
            self.startSwiftRecording()
        }
    }

    /// Start recording using Swift's AVFoundation (not Python)
    /// This uses the app's microphone permission, solving the bundled app issue
    private func startSwiftRecording() {
        status = .recording

        // Play start sound to confirm recording has begun
        audioFeedback.playStartSound()

        // Create recorder with user's silence duration setting
        audioRecorder = AudioRecorder(silenceDuration: settings.silenceDuration)

        // Set up callbacks
        audioRecorder?.onSpeechDetected = { [weak self] in
            // Could update UI here if needed (e.g., show "Speech detected")
            print("[AppState] Speech detected")
        }

        audioRecorder?.onRecordingComplete = { [weak self] result in
            guard let self = self else { return }
            self.handleRecordingComplete(result)
        }

        // Start recording
        do {
            try audioRecorder?.startRecording()
        } catch {
            self.errorMessage = error.localizedDescription
            self.status = .error
            self.audioFeedback.playErrorSound()
            self.audioRecorder = nil
        }
    }

    /// Handle when Swift recording is complete
    private func handleRecordingComplete(_ result: Result<RecordingResult, AudioRecorderError>) {
        switch result {
        case .success(let recordingResult):
            // Recording succeeded - now send to Python for transcription
            status = .transcribing
            transcribeAudioFile(recordingResult.audioPath)

        case .failure(let error):
            if case .noAudioRecorded = error {
                // No speech detected - just go back to ready
                status = .ready
                audioFeedback.playStopSound()
            } else {
                // Real error
                errorMessage = error.localizedDescription
                status = .error
                audioFeedback.playErrorSound()
            }
        }

        audioRecorder = nil
    }

    /// Send recorded audio file to Python for transcription
    private func transcribeAudioFile(_ audioPath: URL) {
        Task { @MainActor in
            do {
                let text = try await pythonBridge.transcribeFile(audioPath: audioPath)
                self.transcribedText = text
                self.status = .ready

                // Play completion sound
                self.audioFeedback.playStopSound()

                // Save to history if we got any text
                if !text.isEmpty {
                    self.historyManager.saveTranscription(
                        text: text,
                        model: self.settings.selectedModel.rawValue
                    )
                }

                // Auto-paste if enabled
                if self.pendingAutoPaste && self.settings.autoPasteEnabled && !text.isEmpty {
                    // Small delay to ensure the previous app is focused
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.pasteManager.pasteText(text)
                    }
                }
            } catch PythonBridgeError.serverBusy {
                self.errorMessage = "Server is busy. Please wait."
                self.status = .error
                self.audioFeedback.playErrorSound()
            } catch PythonBridgeError.serverOffline {
                self.errorMessage = "Server is not running."
                self.isServerOnline = false
                self.status = .error
                self.audioFeedback.playErrorSound()
            } catch PythonBridgeError.serverStarting {
                self.errorMessage = "AI models are still loading. Please wait."
                self.status = .error
                self.audioFeedback.playErrorSound()
            } catch {
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                self.status = .error
                self.audioFeedback.playErrorSound()
            }
        }
    }

    /// Copy the transcribed text to the clipboard
    func copyToClipboard() {
        guard !transcribedText.isEmpty else { return }

        // NSPasteboard is macOS's clipboard
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

    // MARK: - Computed Properties

    /// Icon to show in the menu bar (changes based on status)
    var menuBarIcon: String {
        switch status {
        case .startingServer:
            return "waveform.badge.ellipsis"
        case .downloadingModels:
            return "arrow.down.circle"
        case .ready:
            return "waveform"
        case .recording:
            return "waveform.circle.fill"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .error:
            return "waveform.badge.exclamationmark"
        }
    }

    /// Color for the status indicator dot
    var statusColor: Color {
        switch status {
        case .startingServer:
            return .orange
        case .downloadingModels:
            return .blue
        case .ready:
            return .green
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .error:
            return .red
        }
    }

    // MARK: - Private Methods

    /// Handle changes to the server manager's state
    private func handleServerStateChange(_ serverState: ServerManager.ServerState) {
        switch serverState {
        case .starting:
            // Show "Starting server..." status unless we're actively doing something
            if status == .ready || status == .error {
                status = .startingServer
            }
        case .downloadingModels:
            // Show "Downloading AI models..." unless we're actively recording/transcribing
            if status == .startingServer || status == .ready || status == .error {
                status = .downloadingModels
            }
        case .running:
            // Server is ready - if we were waiting for it, show ready status
            if status == .startingServer || status == .downloadingModels {
                status = .ready
                isServerOnline = true
            }
        case .failed:
            // Server failed to start
            if status == .startingServer || status == .downloadingModels {
                status = .error
                errorMessage = serverManager.errorMessage ?? "Server failed to start"
                isServerOnline = false
            }
        case .notStarted, .stopped:
            // In development mode, user runs server manually
            // Just do normal health checks
            break
        }
    }

    /// Set up the global hotkey callback
    private func setupHotkey() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            guard let self = self else { return }
            // Only start if we're in a state that allows it
            if self.status == .ready || self.status == .error {
                // Start transcription with auto-paste enabled (since triggered by hotkey)
                self.startTranscription(autoPaste: true)
            }
        }
    }

    /// Start listening for the global hotkey (call after app is ready)
    func startHotkeyListening() {
        // Check for accessibility permission and start if granted
        if hotkeyManager.hasAccessibilityPermissionSilent() {
            hotkeyManager.start()
        } else {
            // Will prompt user for permission
            _ = hotkeyManager.checkAccessibilityPermission()
            // Try to start after a delay (user may have granted permission)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.hotkeyManager.start()
            }
        }
    }

    private func startHealthChecks() {
        // Check immediately
        checkServerHealth()

        // Then check every 10 seconds
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkServerHealth()
        }
    }

    private func checkServerHealth() {
        Task { @MainActor in
            let isOnline = await pythonBridge.checkHealth()
            self.isServerOnline = isOnline
        }
    }
}
