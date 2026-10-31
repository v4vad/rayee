//
//  SmartDictationSettingsTab.swift
//  Rayee
//
//  Settings → Smart Dictation
//

import SwiftUI

struct SmartDictationSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var transformManager = MLXTransformManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Clean up my dictation", isOn: $settings.smartDictationEnabled)
            } footer: {
                Text("After each recording, fixes punctuation and capitals and removes filler words like \"um\" — using an AI model on this Mac.")
            }

            Section {
                Picker("Text model", selection: $settings.transformModel) {
                    Text("Automatic (recommended)")
                        .tag(TransformModelSelection.automaticTag)
                    ForEach(TransformModel.allCases) { model in
                        Text(pickerLabel(for: model))
                            .tag(model.rawValue)
                            .disabled(model == .apple && !AppleIntelligence.isAvailable)
                    }
                }
                .onChange(of: settings.transformModel) {
                    // Free the old model now; the new one loads on next use
                    transformManager.unloadModel()
                }
                selectionNote
                modelStatusRow
            } header: {
                Text("Writing model")
            } footer: {
                Text("Bigger models write better but load slower and use more memory. Qwen models download the first time you use them. Apple Intelligence is built into macOS.")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    // MARK: - Selection Note

    /// Under Automatic: which model it picks right now. Under Apple when it can't be used: why transforms will fail.
    @ViewBuilder
    private var selectionNote: some View {
        if let model = transformManager.effectiveModel {
            if TransformModelSelection(tag: settings.transformModel) == .automatic {
                LabeledContent("Currently", value: model.displayName)
            }
        } else {
            Text(MLXTransformError.appleUnavailableMessage)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Model Status Row

    /// "Status ● Ready", the same style as Settings → General.
    @ViewBuilder
    private var modelStatusRow: some View {
        LabeledContent("Status") {
            if transformManager.appleChosenButUnavailable {
                StatusValue(text: "Not available", color: .orange)
            } else if transformManager.usesAppleModel {
                StatusValue(text: "Ready", color: .green)
            } else if transformManager.isModelLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(MLXTransformManager.preparingText(
                        isLoading: true, downloadFraction: transformManager.downloadProgress) ?? "Loading model…")
                }
            } else if transformManager.isModelLoaded {
                StatusValue(text: "Ready", color: .green)
            } else if transformManager.loadError != nil {
                StatusValue(text: "Couldn't load", color: .red)
            } else {
                StatusValue(text: "Loads on first use", color: .secondary)
            }
        }
        if !transformManager.usesAppleModel, let error = transformManager.loadError {
            Text(error)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Picker text for a model. Apple's says what to do when it can't be used yet.
    private func pickerLabel(for model: TransformModel) -> String {
        if model == .apple, let note = AppleIntelligence.unavailableNote {
            return "\(model.displayName) — \(note)"
        }
        return "\(model.displayName) — \(model.approximateDownload)"
    }
}

#Preview {
    SmartDictationSettingsTab()
}
