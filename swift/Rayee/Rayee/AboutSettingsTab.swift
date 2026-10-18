//
//  AboutSettingsTab.swift
//  Rayee
//
//  Settings → About: version, updates, setup again, reset.
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
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rayee").font(.title2.bold())
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("Everything stays on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                Button("Run Setup Again…") {
                    openWindow(id: "setup-guide")
                    NSApp.activate()
                }
                Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { SettingsManager.shared.resetToDefaults() }
        } message: {
            Text("Your hotkey, dictionary and choices go back to how they were when you installed Rayee. History is kept.")
        }
    }
}
