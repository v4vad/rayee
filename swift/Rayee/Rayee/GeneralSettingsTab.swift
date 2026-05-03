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
            // Model Status Section
            Section("Transcription") {
                HStack {
                    Circle()
                        .fill(appState.isWhisperLoading ? Color.blue : (appState.isWhisperReady ? Color.green : Color.red))
                        .frame(width: 10, height: 10)
                    Text("AI Model")
                    Spacer()
                    Text(appState.isWhisperLoading ? "Loading..." : (appState.isWhisperReady ? "Ready" : "Not Loaded"))
                        .foregroundColor(appState.isWhisperLoading ? .blue : (appState.isWhisperReady ? .green : .red))
                }
            }

            // Hotkey Section
            Section("Hotkey") {
                HotkeyPickerView()
            }

            // Auto-Paste Section
            Section {
                Toggle("Auto-paste after transcription", isOn: $settings.autoPasteEnabled)
                    .onChange(of: settings.autoPasteEnabled) { newValue in
                        if newValue {
                            checkAccessibilityPermission()
                        }
                    }

                if settings.autoPasteEnabled {
                    accessibilityStatusView
                }
            } footer: {
                Text("Automatically paste transcribed text where your cursor is")
            }

            // Sound Feedback Section
            Section {
                Toggle("Play sounds", isOn: $settings.soundsEnabled)
            } footer: {
                Text("Play audio feedback when recording starts and stops")
            }

            // Recording Timeout Section
            Section {
                Toggle("Recording timeout", isOn: $settings.timeoutEnabled)
            } footer: {
                Text("When enabled, recording stops after 60 seconds")
            }

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
            } footer: {
                Text("After you stop speaking, recording ends after this many seconds of silence")
            }

            // Fast Transcription Mode
            Section {
                Toggle("Fast transcription mode", isOn: $settings.fastModeEnabled)
            } footer: {
                Text("Faster but slightly less accurate. Best for short dictation.")
            }

            // Adaptive Silence Detection
            Section {
                Toggle("Adaptive silence detection", isOn: $settings.adaptiveVADEnabled)
            } footer: {
                Text("Auto-calibrates to ambient noise for 200ms when recording starts. Useful in varying noise environments.")
            }

            // Reset Button
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
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
