//
//  AppState.swift
//  Rayee
//
//  Tracks the app's current state: what it's doing, transcribed text, errors, etc.
//  This is the "brain" that all UI components read from.
//

import Foundation
import SwiftUI

// What the app is currently doing
enum AppStatus: String {
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

    // Timer for periodic health checks
    private var healthCheckTimer: Timer?

    init() {
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
        status = .recording

        // Call the Python server to record and transcribe
        Task { @MainActor in
            do {
                let text = try await pythonBridge.transcribe()
                self.transcribedText = text
                self.status = .ready

                // Auto-paste if enabled (both from settings and from the autoPaste parameter)
                // The autoPaste parameter is true when triggered by hotkey
                if autoPaste && settings.autoPasteEnabled && !text.isEmpty {
                    // Small delay to ensure the previous app is focused
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.pasteManager.pasteText(text)
                    }
                }
            } catch PythonBridgeError.serverBusy {
                self.errorMessage = "Server is busy. Please wait."
                self.status = .error
            } catch PythonBridgeError.serverOffline {
                self.errorMessage = "Server is not running."
                self.isServerOnline = false
                self.status = .error
            } catch {
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                self.status = .error
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
