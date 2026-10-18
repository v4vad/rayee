//
//  RecordingSettingsTab.swift
//  Rayee
//
//  Settings → Recording: when recording stops by itself.
//

import SwiftUI

struct RecordingSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Stop after silence") {
                    Text("\(Int(settings.silenceDuration)) s")
                        .monospacedDigit()
                }
                Slider(
                    value: $settings.silenceDuration,
                    in: Config.minSilenceDuration...Config.maxSilenceDuration,
                    step: 5
                )
            } footer: {
                Text("When you stop talking, recording ends after this many seconds. You can always stop sooner with your hotkey.")
            }

            Section {
                Toggle("Noisy room mode", isOn: $settings.adaptiveVADEnabled)
            } footer: {
                Text("Listens to the room for a moment when you start, so background noise isn't mistaken for speech.")
            }

            Section {
                LabeledContent("Longest recording", value: "5 minutes")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}
