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

@MainActor
class WhisperKitModelManager: ObservableObject {
    static let shared = WhisperKitModelManager()

    @Published var models: [WKModelInfo] = []
    @Published var selectedModelName: String = "openai_whisper-small"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var downloadTasks: [String: Task<Void, Never>] = [:]

    private init() {
        selectedModelName = UserDefaults.standard.string(forKey: "selectedWhisperKitModel")
            ?? "openai_whisper-small"
    }

    // MARK: - Model Listing

    func refreshModels() async {
        isLoading = true
        errorMessage = nil

        do {
            let available = try await WhisperKit.fetchAvailableModels()
            let downloaded = downloadedModelNames()
            models = available.map { name in
                WKModelInfo(
                    id: name,
                    status: downloaded.contains(name) ? .ready : .notDownloaded,
                    sizeMB: estimatedSizeMB(for: name)
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
                _ = try await WhisperKit.download(variant: name) { [weak self] progress in
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
                selectModel("openai_whisper-small")
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
        let hub = HubApiWrapper()
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

    private func estimatedSizeMB(for name: String) -> Int {
        if name.contains("large-v3-turbo") { return 809 }
        if name.contains("large-v3") { return 1600 }
        if name.contains("distil-large") { return 756 }
        if name.contains("distil-medium") { return 394 }
        if name.contains("distil-small") { return 166 }
        if name.contains("medium") { return 793 }
        if name.contains("small") { return 244 }
        if name.contains("base") { return 145 }
        if name.contains("tiny") { return 75 }
        return 244
    }
}
