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

    // Timer for periodic health checks
    private var healthCheckTimer: Timer?

    init() {
        // Start checking if the server is online every 10 seconds
        startHealthChecks()
    }

    deinit {
        healthCheckTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Start recording and transcription
    func startTranscription() {
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
