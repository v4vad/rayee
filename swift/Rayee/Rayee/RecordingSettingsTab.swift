//
//  RecordingSettingsTab.swift
//  Rayee
//
//  Settings → Recording: when recording stops by itself.
//

import SwiftUI

struct RecordingSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var languages = LivePreviewLanguages()

    /// True when Apple can't show live words for the chosen language (checked once the list has loaded)
    private var previewUnsupported: Bool {
        guard languages.hasLoaded else { return false }
        return !languages.isAvailable || !languages.options.contains { $0.id == settings.livePreviewLanguage }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show words while I speak", isOn: $settings.livePreviewEnabled)
                if settings.livePreviewEnabled {
                    HStack {
                        Picker("Preview language", selection: $settings.livePreviewLanguage) {
                            // Keep the saved choice selectable even if it isn't in the list
                            if !languages.options.contains(where: { $0.id == settings.livePreviewLanguage }) {
                                Text(settings.livePreviewLanguage).tag(settings.livePreviewLanguage)
                            }
                            ForEach(languages.options) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        if let progress = languages.downloadProgress {
                            if progress > 0 {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 60)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Downloading…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                if settings.livePreviewEnabled && previewUnsupported {
                    Text("This Mac can't show live words for this language. Dictation works as usual.")
                } else {
                    Text("See your words in the recorder as you speak. The pasted text still comes from your speech model.")
                }
            }

            Section {
                LabeledContent("Stop after silence") {
                    HStack(spacing: 10) {
                        Slider(
                            value: $settings.silenceDuration,
                            in: Config.minSilenceDuration...Config.maxSilenceDuration,
                            step: 5
                        )
                        .labelsHidden()
                        .frame(width: 180)
                        Text("\(Int(settings.silenceDuration)) s")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                LabeledContent("Longest recording", value: "5 minutes")
            } footer: {
                Text("When you stop talking, recording ends after this many seconds. You can always stop sooner with your shortcut.")
            }

            Section {
                Toggle("Noisy room mode", isOn: $settings.adaptiveVADEnabled)
            } footer: {
                Text("Listens to the room for a moment when you start, so background noise isn't mistaken for speech.")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onChange(of: settings.livePreviewLanguage) { _, newValue in
            languages.choose(newValue)
        }
        .task {
            await languages.load()
            languages.choose(settings.livePreviewLanguage)
        }
    }
}
