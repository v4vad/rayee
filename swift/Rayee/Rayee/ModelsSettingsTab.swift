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
        Form {
            Section {
                ForEach(featuredModels) { row(for: $0) }
            } footer: {
                Text("Turns your voice into text, on this Mac. Bigger models are more accurate but take more space.")
            }

            if !otherModels.isEmpty {
                Section {
                    DisclosureGroup("All models", isExpanded: $showAll) {
                        ForEach(otherModels) { row(for: $0) }
                    }
                }
            }

            if let error = modelManager.errorMessage {
                Section {
                    LabeledContent {
                        Button("Dismiss") { modelManager.errorMessage = nil }
                    } label: {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
        ProgressView("Loading models…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
