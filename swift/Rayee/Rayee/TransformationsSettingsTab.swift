//
//  TransformationsSettingsTab.swift
//  Rayee
//
//  Settings tab for configuring text transformations.
//  Toggle transformations on/off, manage the LLM model, choose which types to show.
//

import SwiftUI

struct TransformationsSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared

    /// Model status from the server
    @State private var modelDownloaded = false
    @State private var modelLoaded = false
    @State private var modelDownloading = false
    @State private var downloadError: String?
    @State private var isCheckingStatus = false

    private let bridge = PythonBridge()

    var body: some View {
        Form {
            // Enable/Disable Section
            Section {
                Toggle("Enable text transformations", isOn: $settings.transformationsEnabled)

                Text("Transform transcribed text using a local AI model (Llama 3.2 1B)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if settings.transformationsEnabled {
                Divider()

                // Model Status Section
                Section {
                    modelStatusRow

                    if let error = downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Divider()

                // Model Options Section
                Section {
                    Toggle("Keep model loaded in memory", isOn: $settings.keepTransformModelLoaded)

                    Text("Uses ~800MB RAM but makes transformations instant. Otherwise the model loads on demand and unloads after 30 seconds.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Visible Transformations Section
                Section {
                    Text("Show these transformations:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

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
        .padding()
        .onAppear { checkModelStatus() }
    }

    // MARK: - Model Status Row

    private var modelStatusRow: some View {
        HStack {
            Text("Transform Model")
            Spacer()

            if modelDownloading {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if modelDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(modelLoaded ? "Loaded" : "Ready")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("Not downloaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Download") {
                    downloadModel()
                }
                .controlSize(.small)
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
                    // Don't allow disabling all transformations
                    if settings.enabledTransformations.count > 1 {
                        settings.enabledTransformations.remove(type.rawValue)
                    }
                }
            }
        )
    }

    private func checkModelStatus() {
        isCheckingStatus = true
        Task {
            if let status = try? await bridge.getTransformStatus() {
                await MainActor.run {
                    modelDownloaded = status.modelDownloaded
                    modelLoaded = status.modelLoaded
                    modelDownloading = status.modelDownloading
                    downloadError = status.downloadError
                    isCheckingStatus = false
                }
            } else {
                await MainActor.run {
                    isCheckingStatus = false
                }
            }
        }
    }

    private func downloadModel() {
        modelDownloading = true
        downloadError = nil
        Task {
            do {
                try await bridge.downloadTransformModel()
                // Poll for completion
                pollDownloadStatus()
            } catch {
                await MainActor.run {
                    modelDownloading = false
                    downloadError = error.localizedDescription
                }
            }
        }
    }

    private func pollDownloadStatus() {
        Task {
            while modelDownloading {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if let status = try? await bridge.getTransformDownloadStatus() {
                    await MainActor.run {
                        switch status.status {
                        case "ready":
                            modelDownloaded = true
                            modelDownloading = false
                        case "error":
                            modelDownloading = false
                            downloadError = status.error ?? "Download failed"
                        case "downloading":
                            break
                        default:
                            modelDownloading = false
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    TransformationsSettingsTab()
}
