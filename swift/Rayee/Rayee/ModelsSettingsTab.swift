//
//  ModelsSettingsTab.swift
//  Rayee
//
//  "Models" settings tab showing WhisperKit transcription models
//  as a card-based list.
//

import SwiftUI

struct ModelsSettingsTab: View {
    @StateObject private var modelManager = WhisperKitModelManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()

            Divider()

            // Model list or loading/error state
            if modelManager.isLoading {
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
            Task { await modelManager.refreshModels() }
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
        if let info = modelManager.models.first(where: { $0.id == modelManager.selectedModelName }) {
            return info.displayName
        }
        return modelManager.selectedModelName
    }

    // MARK: - Model List

    private var standardModels: [WKModelInfo] {
        modelManager.models.filter { !$0.id.contains("distil") }
    }

    private var distilModels: [WKModelInfo] {
        modelManager.models.filter { $0.id.contains("distil") }
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
                    name: model.displayName,
                    description: modelDescription(model),
                    sizeText: model.formattedSize,
                    isActive: modelManager.selectedModelName == model.id,
                    status: rowStatus(model),
                    onUse: { handleUse(model) },
                    onDelete: canDelete(model) ? { handleDelete(model) } : nil
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
                    name: model.displayName,
                    description: modelDescription(model),
                    sizeText: model.formattedSize,
                    isActive: modelManager.selectedModelName == model.id,
                    status: rowStatus(model),
                    onUse: { handleUse(model) },
                    onDelete: canDelete(model) ? { handleDelete(model) } : nil
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
        if let error = modelManager.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                Spacer()
                Button("Dismiss") {
                    modelManager.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Status & Actions

    private func rowStatus(_ model: WKModelInfo) -> ModelRowStatus {
        switch model.status {
        case .notDownloaded:
            return .notDownloaded
        case .downloading(let fraction):
            return .downloading(progress: fraction * 100)
        case .ready:
            return .ready
        case .error(let msg):
            return .error(msg)
        }
    }

    private func canDelete(_ model: WKModelInfo) -> Bool {
        if case .ready = model.status {
            return modelManager.selectedModelName != model.id
        }
        return false
    }

    private func handleUse(_ model: WKModelInfo) {
        if case .ready = model.status {
            modelManager.selectModel(model.id)
            AppState.shared.loadWhisperModel()
        } else {
            modelManager.downloadModel(model.id)
        }
    }

    private func handleDelete(_ model: WKModelInfo) {
        modelManager.deleteModel(model.id)
    }

    // MARK: - Description Helper

    private func modelDescription(_ model: WKModelInfo) -> String {
        let name = model.id
        if name.contains("large-v3-turbo") { return "Fast large model, great accuracy" }
        if name.contains("large-v3") { return "Highest accuracy, slowest" }
        if name.contains("large-v2") { return "High accuracy, large size" }
        if name.contains("distil-large") { return "Distilled large, English only" }
        if name.contains("distil-medium") { return "Distilled medium, English only" }
        if name.contains("distil-small") { return "Distilled small, English only" }
        if name.contains("medium") { return "Good accuracy, moderate speed" }
        if name.contains("small") { return "Balanced speed and accuracy" }
        if name.contains("base") { return "Fast with reasonable accuracy" }
        if name.contains("tiny") { return "Fastest, lower accuracy" }
        return "WhisperKit model"
    }
}
