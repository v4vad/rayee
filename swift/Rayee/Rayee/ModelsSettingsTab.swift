//
//  ModelsSettingsTab.swift
//  Rayee
//
//  Settings → Speech Model
//

import SwiftUI

struct ModelsSettingsTab: View {
    @ObservedObject private var modelManager = WhisperKitModelManager.shared

    @State private var showAll = false

    var body: some View {
        Group {
            if modelManager.isLoading {
                loadingView
            } else {
                modelListView
            }
        }
        .task {
            if modelManager.models.isEmpty {
                await modelManager.refreshModels()
            }
        }
    }

    // MARK: - Model List

    private var featuredModels: [WKModelInfo] {
        let names = WhisperModelCatalog.featured(
            recommended: WhisperModelCatalog.recommended,
            selected: modelManager.selectedModelName,
            available: modelManager.models.map(\.id))
        return names.compactMap { name in modelManager.models.first { $0.id == name } }
    }

    private var otherModels: [WKModelInfo] {
        let featured = Set(featuredModels.map(\.id))
        return modelManager.models.filter { !featured.contains($0.id) }
    }

    private var modelListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Turns your voice into text, on this Mac. Bigger models are more accurate but take more space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                ForEach(featuredModels) { row(for: $0) }

                if !otherModels.isEmpty {
                    DisclosureGroup("Show all models", isExpanded: $showAll) {
                        VStack(spacing: 8) {
                            ForEach(otherModels) { row(for: $0) }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.top, 8)
                }

                errorBannerView
            }
            .padding(20)
        }
    }

    private func row(for model: WKModelInfo) -> some View {
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
        WhisperModelCatalog.description(for: model.id)
    }
}
