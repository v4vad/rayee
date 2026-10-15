import Foundation
import WhisperKit
import SwiftUI

struct WKModelInfo: Identifiable, Equatable {
    let id: String       // WhisperKit model name, e.g. "openai_whisper-small"
    var status: WKModelStatus
    var sizeMB: Int

    var displayName: String {
        id.replacingOccurrences(of: "openai_whisper-", with: "")
          .replacingOccurrences(of: "distil-whisper_distil-", with: "distil-")
    }

    var formattedSize: String {
        sizeMB >= 1000
            ? String(format: "%.1f GB", Double(sizeMB) / 1000.0)
            : "\(sizeMB) MB"
    }
}

enum WKModelStatus: Equatable {
    case notDownloaded
    case downloading(fractionCompleted: Double)
    case ready
    case error(String)
}

/// Which speech model to recommend, plus size and description estimates for the Models tab.
/// Pure logic with no downloads, so it can be unit-tested.
enum WhisperModelCatalog {
    /// Large v3 turbo (September 2024 weights), compressed: close to large-v3 accuracy at a fraction of the size.
    /// Preferred where the Mac supports it (M2 and later).
    static let preferred = "openai_whisper-large-v3-v20240930_turbo_632MB"

    /// The preferred turbo model if this Mac supports it, otherwise WhisperKit's default for this Mac.
    static func recommendedModel(supported: [String], deviceDefault: String) -> String {
        supported.contains(preferred) ? preferred : deviceDefault
    }

    /// The model to recommend on this Mac.
    static var recommended: String {
        let support = WhisperKit.recommendedModels()
        return recommendedModel(supported: support.supported, deviceDefault: support.default)
    }

    /// The default before v0.9. Existing installs that never picked a model keep it.
    static let legacyDefault = "openai_whisper-small"

    /// Saves a speech model choice once, for installs that don't have one yet.
    /// Rayee used to save the choice only when the user picked a model, so an existing user
    /// with nothing saved would otherwise be moved to the new default and a large download.
    static func pinDefaultIfNeeded(in defaults: UserDefaults, isExistingInstall: Bool) {
        guard defaults.string(forKey: SettingsKey.selectedWhisperKitModel) == nil,
              defaults.string(forKey: SettingsKey.selectedModel) == nil else { return }
        defaults.set(isExistingInstall ? legacyDefault : recommended, forKey: SettingsKey.selectedWhisperKitModel)
    }

    /// Download size in MB. Compressed models carry their size in the name, e.g. "..._632MB".
    static func estimatedSizeMB(for name: String) -> Int {
        if let range = name.range(of: #"_(\d+)MB$"#, options: .regularExpression) {
            let digits = name[range].dropFirst().dropLast(2)
            if let size = Int(digits) { return size }
        }
        if name.contains("distil-large") { return 756 }
        if name.contains("distil-medium") { return 394 }
        if name.contains("distil-small") { return 166 }
        if name.contains("large") { return 1600 }
        if name.contains("medium") { return 793 }
        if name.contains("small") { return 244 }
        if name.contains("base") { return 145 }
        if name.contains("tiny") { return 75 }
        return 244
    }

    /// One-line description for the Models tab.
    static func description(for name: String) -> String {
        if name == recommended { return "Recommended — fast large model, great accuracy" }
        if name.contains("distil-large") { return "Distilled large, English only" }
        if name.contains("distil-medium") { return "Distilled medium, English only" }
        if name.contains("distil-small") { return "Distilled small, English only" }
        if name.contains("turbo") { return "Fast large model, great accuracy" }
        if name.contains("large-v3") { return "Highest accuracy, slowest" }
        if name.contains("large-v2") { return "High accuracy, large size" }
        if name.contains("medium") { return "Good accuracy, moderate speed" }
        if name.contains("small") { return "Balanced speed and accuracy" }
        if name.contains("base") { return "Fast with reasonable accuracy" }
        if name.contains("tiny") { return "Fastest, lower accuracy" }
        return "WhisperKit model"
    }
}

@MainActor
class WhisperKitModelManager: ObservableObject {
    static let shared = WhisperKitModelManager()

    @Published var models: [WKModelInfo] = []
    @Published var selectedModelName: String = WhisperModelCatalog.recommended
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        selectedModelName = SettingsManager.shared.selectedWhisperKitModel
    }

    // MARK: - Model Listing

    func refreshModels() async {
        isLoading = true
        errorMessage = nil

        do {
            let available = try await WhisperKit.fetchAvailableModels(downloadBase: Config.whisperKitDownloadBase)
            let downloaded = downloadedModelNames()
            models = available.map { name in
                WKModelInfo(
                    id: name,
                    status: downloaded.contains(name) ? .ready : .notDownloaded,
                    sizeMB: WhisperModelCatalog.estimatedSizeMB(for: name)
                )
            }
        } catch {
            errorMessage = "Failed to load models: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Download

    func downloadModel(_ name: String) {
        guard downloadTasks[name] == nil else { return }

        updateStatus(name, .downloading(fractionCompleted: 0))

        downloadTasks[name] = Task {
            do {
                _ = try await WhisperKit.download(variant: name, downloadBase: Config.whisperKitDownloadBase) { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        self.updateStatus(name, .downloading(fractionCompleted: progress.fractionCompleted))
                    }
                }
                updateStatus(name, .ready)
            } catch {
                updateStatus(name, .error(error.localizedDescription))
            }
            downloadTasks.removeValue(forKey: name)
        }
    }

    // MARK: - Selection

    func selectModel(_ name: String) {
        selectedModelName = name
        UserDefaults.standard.set(name, forKey: "selectedWhisperKitModel")
    }

    // MARK: - Delete

    func deleteModel(_ name: String) {
        let modelDir = whisperKitCacheBase()
        let modelFolder = modelDir.appendingPathComponent(name)

        do {
            if FileManager.default.fileExists(atPath: modelFolder.path) {
                try FileManager.default.removeItem(at: modelFolder)
            }
            updateStatus(name, .notDownloaded)
            if selectedModelName == name {
                selectModel(WhisperModelCatalog.recommended)
            }
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ name: String, _ status: WKModelStatus) {
        if let i = models.firstIndex(where: { $0.id == name }) {
            models[i].status = status
        }
    }

    /// Returns the base directory where WhisperKit caches downloaded models.
    /// Layout: <base>/models/argmaxinc/whisperkit-coreml/<model-name>/
    private func whisperKitCacheBase() -> URL {
        let hub = HubApiWrapper(downloadBase: Config.whisperKitDownloadBase)
        let repo = HubApiWrapper.Repo(id: "argmaxinc/whisperkit-coreml", type: .models)
        return hub.localRepoLocation(repo)
    }

    private func downloadedModelNames() -> Set<String> {
        let base = whisperKitCacheBase()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }
        return Set(
            contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .map { $0.lastPathComponent }
        )
    }
}
