//
//  PythonBridge.swift
//  Rayee
//
//  Handles communication with the Python transcription server.
//  Talks directly over a Unix domain socket to avoid VPN interference
//  and URLSession's httpBody stripping issue with URLProtocol.
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
    private let encoder = JSONEncoder()

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

    // MARK: - Settings

    /// Response from /settings endpoint
    private struct SettingsResponse: Codable {
        let beamSize: Int

        enum CodingKeys: String, CodingKey {
            case beamSize = "beam_size"
        }
    }

    /// Request body for /settings endpoint
    private struct SettingsUpdateRequest: Codable {
        let beamSize: Int

        enum CodingKeys: String, CodingKey {
            case beamSize = "beam_size"
        }
    }

    /// Update server settings (e.g. beam_size for fast mode)
    func updateSettings(beamSize: Int) async {
        do {
            let requestBody = SettingsUpdateRequest(beamSize: beamSize)
            let _: SettingsResponse = try await performRequest(
                endpoint: "/settings",
                method: "POST",
                body: requestBody,
                timeout: Config.regularTimeout
            )
        } catch {
            print("[PythonBridge] Failed to update settings: \(error)")
        }
    }

    // MARK: - Generic Model Action

    /// Perform a model action (download, delete) by endpoint path
    func performModelAction(endpoint: String, method: String = "POST") async throws -> Data {
        let (_, body) = try await socketRequest(
            method: method,
            path: endpoint,
            body: nil,
            headers: [:],
            timeout: Config.regularTimeout
        )
        return body
    }

    // MARK: - Transform Warmup

    /// Preload the transform model so the next transform is instant
    func warmupTransformModel() async {
        do {
            let _: [String: String] = try await performRequest(
                endpoint: "/transform/warmup",
                method: "POST",
                timeout: Config.regularTimeout
            )
        } catch {
            // Warmup is best-effort — don't surface errors
        }
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
    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        timeout: TimeInterval
    ) async throws -> T {
        var headers: [String: String] = [:]
        var bodyData: Data? = nil

        if let body = body {
            headers["Content-Type"] = "application/json"
            bodyData = try encoder.encode(body)
        }

        let (statusCode, responseData) = try await socketRequest(
            method: method,
            path: endpoint,
            body: bodyData,
            headers: headers,
            timeout: timeout
        )

        // Handle status codes
        switch statusCode {
        case 200:
            return try decoder.decode(T.self, from: responseData)

        case 400:
            let detail = extractErrorDetail(from: responseData)
            throw PythonBridgeError.transcriptionFailed(detail ?? "Invalid request")

        case 409:
            throw PythonBridgeError.serverBusy

        case 500:
            let detail = extractErrorDetail(from: responseData)
            throw PythonBridgeError.transcriptionFailed(detail ?? "Server error")

        case 503:
            throw PythonBridgeError.serverStarting

        default:
            throw PythonBridgeError.networkError("Unexpected status: \(statusCode)")
        }
    }

    /// Extract error detail from server error response
    private func extractErrorDetail(from data: Data) -> String? {
        return try? decoder.decode(ErrorResponse.self, from: data).detail
    }

    // MARK: - Direct Unix Socket Communication

    /// Send an HTTP request directly over the Unix domain socket.
    /// Bypasses URLSession entirely to avoid httpBody stripping issues.
    /// Returns (statusCode, responseBody).
    private func socketRequest(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        timeout: TimeInterval
    ) async throws -> (Int, Data) {
        let socketPath = Config.serverSocketPath
        let timeoutSec = max(Int(timeout), 5)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.rawSocketRequest(
                        socketPath: socketPath,
                        method: method,
                        path: path,
                        body: body,
                        headers: headers,
                        timeoutSec: timeoutSec
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Low-level socket request — runs synchronously, must be called off main thread
    private static func rawSocketRequest(
        socketPath: String,
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        timeoutSec: Int
    ) throws -> (Int, Data) {
        // Create Unix domain socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw PythonBridgeError.serverOffline
        }

        // Connect to socket file
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = socketPath.withCString { strncpy(ptr, $0, 104) }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            Darwin.close(fd)
            throw PythonBridgeError.serverOffline
        }

        // Build HTTP request
        var httpText = "\(method) \(path) HTTP/1.1\r\n"
        httpText += "Host: localhost\r\n"
        httpText += "Connection: close\r\n"

        for (key, value) in headers {
            httpText += "\(key): \(value)\r\n"
        }

        if let body = body {
            httpText += "Content-Length: \(body.count)\r\n"
        }

        httpText += "\r\n"

        // Combine headers and body into one data block
        guard var requestData = httpText.data(using: .utf8) else {
            Darwin.close(fd)
            throw PythonBridgeError.networkError("Failed to encode request")
        }

        if let body = body {
            requestData.append(body)
        }

        // Send the complete request
        let sendOK = requestData.withUnsafeBytes { ptr -> Bool in
            var sent = 0
            let total = requestData.count
            while sent < total {
                let n = send(fd, ptr.baseAddress! + sent, total - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }

        guard sendOK else {
            Darwin.close(fd)
            throw PythonBridgeError.networkError("Failed to send request")
        }

        // Read response using poll() for reliable timeout enforcement
        var responseData = Data()
        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        let pollTimeoutMs: Int32 = 1000  // Check every 1 second
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSec))

        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pfd, 1, pollTimeoutMs)

            if pollResult < 0 {
                break  // poll error
            } else if pollResult == 0 {
                continue  // No data yet, check deadline
            }

            let n = recv(fd, buf, bufSize, 0)
            if n <= 0 { break }  // Connection closed or error
            responseData.append(buf, count: n)
        }

        Darwin.close(fd)

        // If no data received, it's a timeout
        if responseData.isEmpty {
            throw PythonBridgeError.serverOffline
        }

        // Parse HTTP response
        let cfMsg = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false).takeRetainedValue()
        responseData.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            CFHTTPMessageAppendBytes(cfMsg, base, responseData.count)
        }

        guard CFHTTPMessageIsHeaderComplete(cfMsg) else {
            throw PythonBridgeError.networkError("Incomplete response from server")
        }

        let statusCode = CFHTTPMessageGetResponseStatusCode(cfMsg)
        let responseBody = (CFHTTPMessageCopyBody(cfMsg)?.takeRetainedValue()) as Data? ?? Data()

        return (statusCode, responseBody)
    }
}
