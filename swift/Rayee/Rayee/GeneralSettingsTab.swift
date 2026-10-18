//
//  GeneralSettingsTab.swift
//  Rayee
//
//  Settings → General: what's wrong (if anything), the hotkey, and the everyday switches.
//

import SwiftUI
import ServiceManagement

struct GeneralSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var status = SystemStatusMonitor.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                statusCard
            }

            Section("Hotkey") {
                HotkeyPickerView()
            }

            Section {
                Toggle("Paste into the app you're using", isOn: $settings.autoPasteEnabled)
                Toggle("Play sounds", isOn: $settings.soundsEnabled)
                Picker("Recorder", selection: $settings.recorderStyle) {
                    ForEach(RecorderStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle("Open Rayee at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = LaunchAtLogin.set($0) }))
            } footer: {
                Text("When there's nowhere to paste, Rayee shows your text with a Copy button instead.")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear {
            status.refresh()
            status.startPolling()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
        .onDisappear { status.stopPolling() }
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        if status.problems.isEmpty {
            Label("Ready to dictate", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            ForEach(status.problems) { problem in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: problem.isBlocking ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                        .foregroundStyle(problem.isBlocking ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(problem.title)
                        if let detail = problem.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let label = problem.fixLabel {
                        Button(label) { status.fix(problem) }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }
}

// MARK: - Launch at Login

/// Opening Rayee at login. macOS stores this itself, so there's no UserDefaults key.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns it on or off and returns the result (unchanged if macOS refused).
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.log("Launch at login change failed: \(error.localizedDescription)", category: "app")
        }
        return isEnabled
    }
}
