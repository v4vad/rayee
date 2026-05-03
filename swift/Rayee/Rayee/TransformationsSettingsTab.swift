//
//  TransformationsSettingsTab.swift
//  Rayee
//
//  Settings tab for configuring text transformations.
//  Toggle transformations on/off, choose which types to show.
//

import SwiftUI

struct TransformationsSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var transformManager = MLXTransformManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable text transformations", isOn: $settings.transformationsEnabled)
            } footer: {
                Text("Transform transcribed text using a local AI model (Llama 3.2 1B)")
            }

            if settings.transformationsEnabled {
                Section("Model") {
                    modelStatusRow
                }

                Section("Visible Transformations") {
                    ForEach(TransformationType.allCases) { type in
                        Toggle(isOn: transformationBinding(for: type)) {
                            HStack(spacing: 8) {
                                Image(systemName: type.icon)
                                    .frame(width: 20)
                                Text(type.label)
                                Spacer()
                                Text("\u{2318}\(type.shortcutNumber)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    // MARK: - Model Status Row

    private var modelStatusRow: some View {
        HStack {
            Text("Transform Model")
            Spacer()

            if transformManager.isModelLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
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

    private func transformationBinding(for type: TransformationType) -> Binding<Bool> {
        Binding(
            get: { settings.enabledTransformations.contains(type.rawValue) },
            set: { enabled in
                if enabled {
                    settings.enabledTransformations.insert(type.rawValue)
                } else {
                    if settings.enabledTransformations.count > 1 {
                        settings.enabledTransformations.remove(type.rawValue)
                    }
                }
            }
        )
    }
}

#Preview {
    TransformationsSettingsTab()
}
