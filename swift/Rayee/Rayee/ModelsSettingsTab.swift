//
//  ModelsSettingsTab.swift
//  Rayee
//
//  "Models" settings tab showing Faster-Whisper transcription models
//  as a card-based list.
//

import SwiftUI

struct ModelsSettingsTab: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var fwManager = FasterWhisperManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()

            Divider()

            // Model list or loading/error state
            if fwManager.isLoading {
                loadingView
            } else {
                modelListView
            }

            Spacer(minLength: 0)

            // Error banner
            errorBannerView
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .onAppear {
            Task {
                await fwManager.refreshModels()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.blue)
                Text("Transcription Models")
                    .font(.headline)
            }

            HStack {
                Text("Active:")
                    .foregroundColor(.secondary)
                Text(activeModelName)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Name of the currently active model
    private var activeModelName: String {
        if let fwName = fwManager.selectedModelName,
           let fwModel = fwManager.models.first(where: { $0.id == fwName }) {
            return fwModel.name
        }
        return settings.selectedModel.displayName
    }

    // MARK: - Model List

    private var standardModels: [FWModelInfo] {
        fwManager.models.filter { $0.category == "standard" }
    }

    private var distilModels: [FWModelInfo] {
        fwManager.models.filter { $0.category == "distil" }
    }

    private var modelListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                standardModelsSection

                if !distilModels.isEmpty {
                    distilModelsSection
                }
            }
            .padding()
        }
    }

    // MARK: - Standard Models Section

    private var standardModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Standard Models", subtitle: "Work on all Macs")

            ForEach(standardModels) { model in
                ModelRow(
                    name: model.name,
                    description: model.description,
                    sizeText: model.formattedSize,
                    isActive: isFWModelActive(model.id),
                    status: fwRowStatus(model),
                    onUse: { handleFWUse(model) },
                    onDelete: fwCanDelete(model) ? { handleFWDelete(model) } : nil
                )
            }
        }
    }

    // MARK: - Distil Models Section

    private var distilModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "Distil Models (English Only)", subtitle: "Faster, English transcription only")

            ForEach(distilModels) { model in
                ModelRow(
                    name: model.name,
                    description: model.description,
                    sizeText: model.formattedSize,
                    isActive: isFWModelActive(model.id),
                    status: fwRowStatus(model),
                    onUse: { handleFWUse(model) },
                    onDelete: fwCanDelete(model) ? { handleFWDelete(model) } : nil
                )
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading models...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private var errorBannerView: some View {
        if let error = fwManager.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                Spacer()
                Button("Dismiss") {
                    fwManager.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - FW Status & Actions

    private func isFWModelActive(_ name: String) -> Bool {
        fwManager.selectedModelName == name
    }

    private func fwRowStatus(_ model: FWModelInfo) -> ModelRowStatus {
        switch model.status {
        case .notDownloaded: return .notDownloaded
        case .downloading: return .downloading(progress: nil)
        case .ready: return .ready
        case .error(let msg): return .error(msg)
        }
    }

    private func fwCanDelete(_ model: FWModelInfo) -> Bool {
        if case .ready = model.status {
            return !isFWModelActive(model.id)
        }
        return false
    }

    private func handleFWUse(_ model: FWModelInfo) {
        Task {
            if case .ready = model.status {
                await fwManager.selectModel(model.id)
            } else {
                await fwManager.downloadAndSelectModel(model.id)
            }
        }
    }

    private func handleFWDelete(_ model: FWModelInfo) {
        Task { await fwManager.deleteModel(model.id) }
    }
}
