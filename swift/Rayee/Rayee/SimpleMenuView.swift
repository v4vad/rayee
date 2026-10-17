//
//  SimpleMenuView.swift
//  Rayee
//
//  The menu-bar menu: a warning only when something is wrong, then Record, History,
//  Settings, updates and Quit.
//

import SwiftUI

struct SimpleMenuView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var status = SystemStatusMonitor.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let problem = status.problems.first(where: \.isBlocking) {
                Button("⚠︎ \(problem.title) — Fix…") {
                    openSettingsWindow(section: .general)
                }
                Divider()
            }

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

            Divider()

            Button("History…") {
                openSettingsWindow(section: .history)
            }

            Button("Settings…") {
                openSettingsWindow(section: nil)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Check for Updates…") {
                UpdateManager.shared.checkForUpdates()
            }
            .disabled(!UpdateManager.shared.canCheckForUpdates)

            Divider()

            Button("Quit Rayee") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear { status.refresh() }
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

    private func openSettingsWindow(section: SettingsSection?) {
        if let section {
            UserDefaults.standard.set(section.rawValue, forKey: "settingsTab")
            NotificationCenter.default.post(name: .openSettingsSection, object: nil)
        }
        openSettings()
        NSApp.activate()
    }
}
