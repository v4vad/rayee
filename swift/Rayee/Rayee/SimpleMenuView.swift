//
//  SimpleMenuView.swift
//  Rayee
//
//  A simple dropdown menu for the menu bar.
//  Contains basic actions: Record, Vocabulary, History, Settings, Quit.
//

import SwiftUI

struct SimpleMenuView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var hasCheckedFirstLaunch = false

    var body: some View {
        // Record button with hotkey hint
        Button(action: {
            if appState.status == .recording {
                appState.stopRecording()
            } else {
                appState.startTranscription(autoPaste: true)
            }
        }) {
            HStack {
                Text(recordButtonText)
                Spacer()
                Text(SettingsManager.shared.hotkeyConfig.displayString)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(!canRecord)
        .keyboardShortcut(.space, modifiers: .option)

        Divider()

        // Vocabulary - opens Settings to Vocabulary tab
        Button("Vocabulary...") {
            openSettingsWindow(tab: "vocabulary")
        }

        // History - opens Settings to History tab
        Button("History...") {
            openSettingsWindow(tab: "history")
        }

        // Upload Audio - opens Settings to Uploads tab
        Button("Upload Audio...") {
            openSettingsWindow(tab: "uploads")
        }

        Divider()

        // System Status (setup guide)
        Button("System Status...") {
            openWindow(id: "setup-guide")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        // Settings
        Button("Settings...") {
            openSettingsWindow(tab: nil)
        }
        .keyboardShortcut(",", modifiers: .command)

        // Check for Updates
        Button("Check for Updates...") {
            UpdateManager.shared.checkForUpdates()
        }
        .disabled(!UpdateManager.shared.canCheckForUpdates)

        Divider()

        // Quit
        Button("Quit Rayee") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .onAppear {
            // Show setup guide on first launch
            if !hasCheckedFirstLaunch {
                hasCheckedFirstLaunch = true
                if !SettingsManager.shared.hasCompletedSetup {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        openWindow(id: "setup-guide")
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var recordButtonText: String {
        switch appState.status {
        case .loadingModels: return "Loading models..."
        case .ready, .error: return "Record"
        case .recording: return "Stop Recording"
        case .transcribing: return "Transcribing..."
        }
    }

    private var canRecord: Bool {
        switch appState.status {
        case .ready, .error, .recording: return true
        case .loadingModels, .transcribing: return false
        }
    }

    // MARK: - Helper Methods

    private func openSettingsWindow(tab: String?) {
        if let tab = tab {
            UserDefaults.standard.set(tab, forKey: "settingsTab")
        }
        openSettings()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
