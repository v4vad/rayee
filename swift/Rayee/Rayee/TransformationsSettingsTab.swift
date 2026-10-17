//
//  TransformationsSettingsTab.swift
//  Rayee
//
//  Settings tab for Smart Dictation and the text model it uses.
//

import SwiftUI

struct TransformationsSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var transformManager = MLXTransformManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Auto-clean after transcription", isOn: $settings.smartDictationEnabled)
            } header: {
                Text("Smart Dictation")
            } footer: {
                Text("After every recording, fixes grammar and punctuation and removes filler words like \"um\" — automatically.")
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
                .onChange(of: settings.transformModel) { _ in
                    // Free the old model now; the new one loads on next use
                    transformManager.unloadModel()
                }
                selectionNote
                modelStatusRow
            } header: {
                Text("Model")
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
                Text("Currently: \(model.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            Text(MLXTransformError.appleUnavailableMessage)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    // MARK: - Model Status Row

    private var modelStatusRow: some View {
        HStack {
            Text("Transform Model")
            Spacer()

            if transformManager.appleChosenButUnavailable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Apple Intelligence isn't ready")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if transformManager.usesAppleModel {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Built in, ready")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if transformManager.isModelLoading {
                ProgressView()
                    .controlSize(.small)
                Text(MLXTransformManager.preparingText(
                    isLoading: true, downloadFraction: transformManager.downloadProgress) ?? "Loading model…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if transformManager.isModelLoaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Loaded")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if let error = transformManager.loadError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Loads on first use")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
    TransformationsSettingsTab()
}
