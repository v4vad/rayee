//
//  FasterWhisperManager.swift
//  Rayee
//
//  Manages Faster-Whisper model download, delete, and status.
//

import Foundation
import SwiftUI

// MARK: - Shared Unix Socket Session

/// URLSession that routes requests through Unix domain socket
private let unixSocketSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.protocolClasses = [UnixSocketProtocol.self]
    return URLSession(configuration: config)
}()

// MARK: - API Response Types

struct FWModelData: Codable {
    let name: String
    let description: String
    let sizeMB: Int
    let isCurrent: Bool
    let isLoaded: Bool
    let status: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case name, description, status, error
        case sizeMB = "size_mb"
        case isCurrent = "is_current"
        case isLoaded = "is_loaded"
    }
}

struct FWModelsResponse: Codable {
    let currentModel: String
    let availableModels: [FWModelData]

    enum CodingKeys: String, CodingKey {
        case currentModel = "current_model"
        case availableModels = "available_models"
    }
}

struct FWDownloadResponse: Codable {
    let modelName: String
    let status: String
    let error: String?

    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case status, error
    }
}

struct FWActionResponse: Codable {
    let success: Bool
    let message: String
    let modelName: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case modelName = "model_name"
    }
}

private struct FWModelSwitchRequest: Codable {
    let model: String
}

// MARK: - FW Model Info

struct FWModelInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let sizeMB: Int
    var status: FWModelStatus

    var formattedSize: String {
        if sizeMB >= 1000 {
            return String(format: "%.1f GB", Double(sizeMB) / 1000.0)
        }
        return "\(sizeMB) MB"
    }
}

enum FWModelStatus: Equatable {
    case notDownloaded
    case downloading
    case ready
    case error(String)

    static func from(status: String, error: String? = nil) -> FWModelStatus {
        switch status {
        case "not_downloaded":
            return .notDownloaded
        case "downloading":
            return .downloading
        case "ready":
            return .ready
        case "error":
            return .error(error ?? "Unknown error")
        default:
            return .notDownloaded
        }
    }
}

// MARK: - Faster-Whisper Model Manager

@MainActor
class FasterWhisperManager: ObservableObject {
    static let shared = FasterWhisperManager()

    @Published var models: [FWModelInfo] = []
    @Published var selectedModelName: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let decoder = JSONDecoder()
    private var downloadPollingTask: Task<Void, Never>?
    private var pendingAutoSelectModelName: String?

    private init() {}

    func refreshModels() async {
        isLoading = true
        errorMessage = nil

        do {
            let response: FWModelsResponse = try await performRequest(
                endpoint: "/models",
                method: "GET"
            )

            selectedModelName = response.currentModel

            models = response.availableModels.map { data in
                FWModelInfo(
                    id: data.name,
                    name: TranscriptionModel(rawValue: data.name)?.displayName ?? data.name,
                    description: data.description,
                    sizeMB: data.sizeMB,
                    status: FWModelStatus.from(status: data.status, error: data.error)
                )
            }
        } catch {
            errorMessage = "Failed to load models: \(error.localizedDescription)"
            print("[FWManager] Error refreshing models: \(error)")
        }

        isLoading = false
    }

    /// Start downloading a Faster-Whisper model
    func downloadModel(_ name: String) async {
        updateModelStatus(name, status: .downloading)
        errorMessage = nil

        do {
            let response: FWDownloadResponse = try await performRequest(
                endpoint: "/models/download/\(name)",
                method: "POST"
            )

            // If already ready, update status and auto-select immediately
            if response.status == "ready" {
                updateModelStatus(name, status: .ready)
                if pendingAutoSelectModelName == name {
                    pendingAutoSelectModelName = nil
                    await selectModel(name)
                }
                return
            }

            startPollingProgress(name)
        } catch {
            updateModelStatus(name, status: .error(error.localizedDescription))
            errorMessage = "Failed to start download: \(error.localizedDescription)"
        }
    }

    /// Download a model and auto-select it when ready
    func downloadAndSelectModel(_ name: String) async {
        pendingAutoSelectModelName = name
        await downloadModel(name)
    }

    /// Select a Faster-Whisper model for transcription
    func selectModel(_ name: String) async {
        errorMessage = nil

        do {
            let body = FWModelSwitchRequest(model: name)
            let _: [String: String] = try await performRequest(
                endpoint: "/model",
                method: "POST",
                body: body
            )
            selectedModelName = name
        } catch {
            errorMessage = "Failed to select model: \(error.localizedDescription)"
        }
    }

    /// Delete a downloaded Faster-Whisper model
    func deleteModel(_ name: String) async {
        do {
            let response: FWActionResponse = try await performRequest(
                endpoint: "/models/\(name)",
                method: "DELETE"
            )

            if response.success {
                updateModelStatus(name, status: .notDownloaded)
            } else {
                errorMessage = response.message
            }
        } catch {
            errorMessage = "Failed to delete model: \(error.localizedDescription)"
        }
    }

    private func updateModelStatus(_ name: String, status: FWModelStatus) {
        if let index = models.firstIndex(where: { $0.id == name }) {
            models[index].status = status
        }
    }

    private func startPollingProgress(_ name: String) {
        downloadPollingTask?.cancel()

        downloadPollingTask = Task {
            while !Task.isCancelled {
                do {
                    let response: FWDownloadResponse = try await performRequest(
                        endpoint: "/models/download_status/\(name)",
                        method: "GET"
                    )

                    let status = FWModelStatus.from(
                        status: response.status,
                        error: response.error
                    )

                    await MainActor.run {
                        updateModelStatus(name, status: status)
                    }

                    if response.status == "ready" {
                        if self.pendingAutoSelectModelName == name {
                            self.pendingAutoSelectModelName = nil
                            await self.selectModel(name)
                        }
                        break
                    }
                    if response.status == "error" {
                        self.pendingAutoSelectModelName = nil
                        break
                    }

                    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                } catch {
                    print("[FWManager] Polling error: \(error)")
                    break
                }
            }
        }
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(Config.serverBaseURL)\(endpoint)") else {
            throw PythonBridgeError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "POST" ? Config.transcriptionTimeout : Config.regularTimeout

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await unixSocketSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PythonBridgeError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 200 {
            return try decoder.decode(T.self, from: data)
        } else {
            if let errorResponse = try? decoder.decode(FWActionResponse.self, from: data) {
                throw PythonBridgeError.networkError(errorResponse.message)
            }
            throw PythonBridgeError.networkError("Request failed with status \(httpResponse.statusCode)")
        }
    }
}
