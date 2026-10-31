//
//  AboutSettingsTab.swift
//  Rayee
//
//  Settings → About: version, updates, setup again, reset.
//  Laid out like System Settings → General → About: a centred header, then labelled rows.
//

import SwiftUI

struct AboutSettingsTab: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updates = UpdateManager.shared
    @State private var confirmingReset = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Updates") {
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            } header: {
                header
            }

            Section {
                LabeledContent {
                    Button("Run Setup Again…") {
                        openWindow(id: "setup-guide")
                        NSApp.activate()
                    }
                } label: {
                    Text("Setup guide")
                    Text("Walks you through permissions, the speech model and your shortcut.")
                }
                LabeledContent {
                    Button("Reset…", role: .destructive) { confirmingReset = true }
                } label: {
                    Text("Reset all settings")
                    Text("Your shortcut, dictionary and choices go back to how they were. History is kept.")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { SettingsManager.shared.resetToDefaults() }
        } message: {
            Text("Your hotkey, dictionary and choices go back to how they were when you installed Rayee. History is kept.")
        }
    }

    /// Icon, name and a one-line promise, centred above the rows
    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Rayee")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text("Everything stays on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
        .textCase(nil)
    }
}
