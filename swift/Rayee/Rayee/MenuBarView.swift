//
//  MenuBarView.swift
//  Rayee
//
//  The popup window that appears when you click the menu bar icon.
//  Shows status, transcribed text, and control buttons.
//

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            headerSection

            Divider()

            // Transcribed text display
            textDisplaySection

            // Action buttons
            buttonSection

            Divider()

            // Footer with server status
            footerSection
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            Text("Rayee")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            StatusIndicator(
                status: appState.status,
                color: appState.statusColor
            )
        }
    }

    // MARK: - Text Display Section

    private var textDisplaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Error banner (if there's an error)
            if let error = appState.errorMessage {
                errorBanner(message: error)
            }

            // Text display area
            ScrollView {
                Text(appState.transcribedText.isEmpty ? "Your transcribed text will appear here..." : appState.transcribedText)
                    .font(.system(size: 13))
                    .foregroundColor(appState.transcribedText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)  // Allow text selection
            }
            .frame(height: 100)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Button Section

    private var buttonSection: some View {
        HStack(spacing: 12) {
            // Start Recording button
            Button(action: {
                appState.startTranscription()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: buttonIcon)
                    Text(buttonText)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStartRecording)
            .tint(buttonTint)

            // Copy button
            Button(action: {
                appState.copyToClipboard()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
            }
            .buttonStyle(.bordered)
            .disabled(appState.transcribedText.isEmpty)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack {
            // Server status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isServerOnline ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text("Server: \(appState.isServerOnline ? "Online" : "Offline")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Quit button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.primary)

            Spacer()

            Button(action: {
                appState.clearError()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Computed Properties

    private var canStartRecording: Bool {
        appState.status == .ready || appState.status == .error
    }

    private var buttonIcon: String {
        switch appState.status {
        case .ready, .error:
            return "mic.fill"
        case .recording:
            return "waveform"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        }
    }

    private var buttonText: String {
        switch appState.status {
        case .ready, .error:
            return "Start Recording"
        case .recording:
            return "Listening..."
        case .transcribing:
            return "Transcribing..."
        }
    }

    private var buttonTint: Color {
        switch appState.status {
        case .ready, .error:
            return .accentColor
        case .recording:
            return .red
        case .transcribing:
            return .orange
        }
    }
}

// Preview for Xcode's canvas
#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
