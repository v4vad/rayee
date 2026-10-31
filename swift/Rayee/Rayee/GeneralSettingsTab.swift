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
                statusRows
            }

            Section {
                HotkeyPickerView()
            } footer: {
                Text("Press it in any app to start dictating, and again to stop.")
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

    // MARK: - Status

    private var blockingProblems: [SystemProblem] {
        status.problems.filter(\.isBlocking)
    }

    /// "Status ● Ready" like System Settings, then one row per thing to fix, each with its button.
    @ViewBuilder
    private var statusRows: some View {
        LabeledContent("Status") {
            if !blockingProblems.isEmpty {
                StatusValue(text: "Needs attention", color: .orange)
            } else if status.problems.contains(.speechModelLoading) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading speech model…")
                }
            } else {
                StatusValue(text: "Ready", color: .green)
            }
        }
        ForEach(blockingProblems) { problem in
            LabeledContent {
                if let label = problem.fixLabel {
                    Button(label) { status.fix(problem) }
                }
            } label: {
                Text(problem.title)
                if let detail = problem.detail {
                    Text(detail)
                }
            }
        }
    }
}

/// A status value the way System Settings shows one: a small coloured dot, then a word or two.
struct StatusValue: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
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
