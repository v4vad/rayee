//
//  PythonBridge.swift
//  Rayee
//
//  Handles communication with the Python transcription server.
//  Makes HTTP requests to localhost:8765 for health checks, status, and transcription.
//

import Foundation

// Errors that can occur when communicating with the server
enum PythonBridgeError: LocalizedError {
    case serverOffline
    case serverStarting
    case serverBusy
    case transcriptionFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .serverOffline:
            return "Cannot connect to Python server. Is it running?"
        case .serverStarting:
            return "Server is still starting up. Please wait a moment."
        case .serverBusy:
            return "Server is busy. Please wait."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Response Types

/// Response from /status endpoint
private struct StatusResponse: Codable {
    let status: String
}

/// Response from /transcribe endpoint
private struct TranscribeResponse: Codable {
    let text: String
    let status: String
}

/// Response from /health endpoint
private struct HealthResponse: Codable {
    let status: String
}

/// Response from /startup_status endpoint
struct StartupStatusResponse: Codable {
    let state: String   // not_started, downloading_vad, downloading_whisper, ready, failed
    let message: String
    let error: String?
}

/// Error response from server
private struct ErrorResponse: Codable {
    let detail: String?
}

// MARK: - Request Types

/// Request body for /transcribe endpoint
private struct TranscribeRequest: Codable {
    let silenceDuration: Double

    enum CodingKeys: String, CodingKey {
        case silenceDuration = "silence_duration"
    }
}

/// Request body for /transcribe_file endpoint
private struct TranscribeFileRequest: Codable {
    let audioPath: String

    enum CodingKeys: String, CodingKey {
        case audioPath = "audio_path"
    }
}

// MARK: - PythonBridge

class PythonBridge {
    private let decoder = JSONDecoder()

    /// URLSession configured to route requests through Unix domain socket
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [UnixSocketProtocol.self]
        return URLSession(configuration: config)
    }()

    // MARK: - Public Methods

    /// Check if the Python server is running
    func checkHealth() async -> Bool {
        return await performHealthCheck()
    }

    /// Check health with retries - used during startup when server may still be initializing
    func checkHealthWithRetry() async -> Bool {
        for attempt in 1...Config.startupRetryAttempts {
            if await performHealthCheck() {
                print("[PythonBridge] Server healthy on attempt \(attempt)")
                return true
            }

            if attempt < Config.startupRetryAttempts {
                print("[PythonBridge] Health check attempt \(attempt)/\(Config.startupRetryAttempts) failed, retrying...")
                try? await Task.sleep(nanoseconds: UInt64(Config.startupRetryDelay * 1_000_000_000))
            }
        }

        print("[PythonBridge] Server did not become healthy after \(Config.startupRetryAttempts) attempts")
        return false
    }

    /// Get the current startup/model loading status
    func getStartupStatus() async -> StartupStatusResponse? {
        do {
            return try await performRequest(
                endpoint: "/startup_status",
                timeout: Config.regularTimeout
            )
        } catch {
            return nil
        }
    }

    /// Get current server status (idle, recording, transcribing)
    func getStatus() async throws -> String {
        let response: StatusResponse = try await performRequest(
            endpoint: "/status",
            timeout: Config.regularTimeout
        )
        return response.status
    }

    /// Start recording and transcription (Python-side recording)
    func transcribe(silenceDuration: Double = Config.defaultSilenceDuration) async throws -> String {
        let requestBody = TranscribeRequest(silenceDuration: silenceDuration)
        let response: TranscribeResponse = try await performRequest(
            endpoint: "/transcribe",
            method: "POST",
            body: requestBody,
            timeout: Config.transcriptionTimeout
        )
        return response.text
    }

    /// Transcribe audio from a WAV file (Swift-side recording)
    func transcribeFile(audioPath: URL) async throws -> String {
        let requestBody = TranscribeFileRequest(audioPath: audioPath.path)
        let response: TranscribeResponse = try await performRequest(
            endpoint: "/transcribe_file",
            method: "POST",
            body: requestBody,
            timeout: Config.transcriptionTimeout
        )
        return response.text
    }

    /// Transcribe an uploaded audio file in the background (doesn't block recording).
    /// Calls /transcribe_upload which bypasses the state machine.
    func transcribeUploadedFile(audioPath: URL) async throws -> String {
        let requestBody = TranscribeFileRequest(audioPath: audioPath.path)
        let response: TranscribeResponse = try await performRequest(
            endpoint: "/transcribe_upload",
            method: "POST",
            body: requestBody,
            timeout: Config.fileUploadTranscriptionTimeout
        )
        return response.text
    }

    /// Transcribe an uploaded audio file in blocking mode (blocks recording).
    /// Calls /transcribe_file which uses the state machine.
    func transcribeUploadedFileBlocking(audioPath: URL) async throws -> String {
        let requestBody = TranscribeFileRequest(audioPath: audioPath.path)
        let response: TranscribeResponse = try await performRequest(
            endpoint: "/transcribe_file",
            method: "POST",
            body: requestBody,
            timeout: Config.fileUploadTranscriptionTimeout
        )
        return response.text
    }

    // MARK: - Generic Model Action

    /// Perform a model action (download, delete) by endpoint path
    func performModelAction(endpoint: String, method: String = "POST") async throws -> Data {
        guard let url = URL(string: "\(Config.serverBaseURL)\(endpoint)") else {
            throw PythonBridgeError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Config.regularTimeout

        let (data, _) = try await session.data(for: request)
        return data
    }

    // MARK: - Text Transformation Methods

    /// Transform text using the local LLM
    func transformText(text: String, type: String) async throws -> TransformAPIResponse {
        let requestBody = TransformRequestBody(text: text, transformationType: type)
        return try await performRequest(
            endpoint: "/transform",
            method: "POST",
            body: requestBody,
            timeout: Config.transformationTimeout
        )
    }

    /// Get the transform model status
    func getTransformStatus() async throws -> TransformStatusAPIResponse {
        return try await performRequest(
            endpoint: "/transform/status",
            timeout: Config.regularTimeout
        )
    }

    /// Trigger download of the transform model
    func downloadTransformModel() async throws -> TransformDownloadAPIResponse {
        return try await performRequest(
            endpoint: "/transform/download",
            method: "POST",
            timeout: Config.regularTimeout
        )
    }

    /// Get download status of the transform model
    func getTransformDownloadStatus() async throws -> TransformDownloadAPIResponse {
        return try await performRequest(
            endpoint: "/transform/download_status",
            timeout: Config.regularTimeout
        )
    }

    // MARK: - Private Helpers

    /// Perform a single health check request
    private func performHealthCheck() async -> Bool {
        do {
            let response: HealthResponse = try await performRequest(
                endpoint: "/health",
                timeout: Config.regularTimeout
            )
            return response.status == "ok"
        } catch {
            return false
        }
    }

    /// Generic HTTP request helper that handles all common patterns
    /// - Parameters:
    ///   - endpoint: The API path (e.g., "/health", "/transcribe")
    ///   - method: HTTP method (defaults to GET)
    ///   - body: Optional request body (will be JSON encoded)
    ///   - timeout: Request timeout
    /// - Returns: Decoded response of type T
    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        timeout: TimeInterval
    ) async throws -> T {
        guard let url = URL(string: "\(Config.serverBaseURL)\(endpoint)") else {
            throw PythonBridgeError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PythonBridgeError.networkError("Invalid response")
            }

            // Handle status codes
            switch httpResponse.statusCode {
            case 200:
                return try decoder.decode(T.self, from: data)

            case 400:
                // Bad request (e.g., file not found)
                let detail = extractErrorDetail(from: data)
                throw PythonBridgeError.transcriptionFailed(detail ?? "Invalid request")

            case 409:
                throw PythonBridgeError.serverBusy

            case 500:
                let detail = extractErrorDetail(from: data)
                throw PythonBridgeError.transcriptionFailed(detail ?? "Server error")

            case 503:
                throw PythonBridgeError.serverStarting

            default:
                throw PythonBridgeError.networkError("Unexpected status: \(httpResponse.statusCode)")
            }

        } catch is URLError {
            throw PythonBridgeError.serverOffline
        } catch let error as PythonBridgeError {
            throw error
        } catch let error as DecodingError {
            throw PythonBridgeError.networkError("Failed to parse response: \(error.localizedDescription)")
        } catch {
            throw PythonBridgeError.networkError(error.localizedDescription)
        }
    }

    /// Extract error detail from server error response
    private func extractErrorDetail(from data: Data) -> String? {
        return try? decoder.decode(ErrorResponse.self, from: data).detail
    }
}
