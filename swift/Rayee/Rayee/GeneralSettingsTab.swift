//
//  GeneralSettingsTab.swift
//  Rayee
//
//  The "General" tab in Settings, extracted from SettingsView
//  to keep file sizes under 300 lines.
//

import SwiftUI
import Carbon.HIToolbox

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @Binding var isRecordingHotkey: Bool
    @Binding var showingAccessibilityAlert: Bool

    var body: some View {
        Form {
            // Server Status Section
            Section {
                HStack {
                    Circle()
                        .fill(appState.isServerOnline ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text("Server Status")
                    Spacer()
                    Text(appState.isServerOnline ? "Online" : "Offline")
                        .foregroundColor(appState.isServerOnline ? .green : .red)
                }
            }

            Divider()

            // Hotkey Section
            Section {
                HStack {
                    Text("Global Hotkey")
                    Spacer()
                    hotkeyRecorderButton
                }
                Text("Press this keyboard shortcut anywhere to start transcription")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Model Selection Section
            Section {
                Picker("AI Model", selection: $settings.selectedModel) {
                    ForEach(TranscriptionModel.allCases) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                        }
                        .tag(model)
                    }
                }
                .pickerStyle(.menu)

                Text(settings.selectedModel.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Auto-Paste Section
            Section {
                Toggle("Auto-paste after transcription", isOn: $settings.autoPasteEnabled)
                    .onChange(of: settings.autoPasteEnabled) { newValue in
                        if newValue {
                            checkAccessibilityPermission()
                        }
                    }

                Text("Automatically paste transcribed text where your cursor is")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if settings.autoPasteEnabled {
                    accessibilityStatusView
                }
            }

            Divider()

            // Sound Feedback Section
            Section {
                Toggle("Play sounds", isOn: $settings.soundsEnabled)

                Text("Play audio feedback when recording starts and stops")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Recording Timeout Section
            Section {
                Toggle("Recording timeout", isOn: $settings.timeoutEnabled)

                Text("When enabled, recording stops after 60 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Silence Detection Section
            Section {
                HStack {
                    Text("Silence detection")
                    Spacer()
                    Text(String(format: "%.0fs", settings.silenceDuration))
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: $settings.silenceDuration,
                    in: Config.minSilenceDuration...Config.maxSilenceDuration,
                    step: 5
                )

                Text("After you stop speaking, recording ends after this many seconds of silence")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Hotkey Recorder Button
    private var hotkeyRecorderButton: some View {
        Button(action: {
            isRecordingHotkey.toggle()
        }) {
            HStack(spacing: 4) {
                if isRecordingHotkey {
                    Text("Press keys...")
                        .foregroundColor(.orange)
                } else {
                    Text(settings.hotkeyConfig.displayString)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecordingHotkey ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecordingHotkey ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accessibility Status View
    private var accessibilityStatusView: some View {
        HStack {
            if PasteManager.shared.hasAccessibilityPermission() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Accessibility permission granted")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Accessibility permission needed")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
                Button("Grant Access") {
                    openAccessibilitySettings()
                }
                .font(.caption)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helper Methods

    private func checkAccessibilityPermission() {
        if !PasteManager.shared.hasAccessibilityPermission() {
            showingAccessibilityAlert = true
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
