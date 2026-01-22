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
    case serverBusy
    case transcriptionFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .serverOffline:
            return "Cannot connect to Python server. Is it running?"
        case .serverBusy:
            return "Server is busy. Please wait."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// Response from /status endpoint
private struct StatusResponse: Codable {
    let status: String
}

// Response from /transcribe endpoint
private struct TranscribeResponse: Codable {
    let text: String
    let status: String
}

// Response from /health endpoint
private struct HealthResponse: Codable {
    let status: String
}

// Error response from server
private struct ErrorResponse: Codable {
    let detail: String?
}

// Request body for /transcribe endpoint
private struct TranscribeRequest: Codable {
    let silenceDuration: Double

    // Maps Swift camelCase to Python snake_case
    enum CodingKeys: String, CodingKey {
        case silenceDuration = "silence_duration"
    }
}

class PythonBridge {
    // Server URL - Python server runs on localhost port 8765
    private let baseURL = "http://127.0.0.1:8765"

    // JSON decoder for parsing responses
    private let decoder = JSONDecoder()

    // Timeout for regular requests (5 seconds)
    private let regularTimeout: TimeInterval = 5.0

    // Longer timeout for transcription (120 seconds - recording can take a while)
    private let transcriptionTimeout: TimeInterval = 120.0

    // MARK: - Public Methods

    /// Check if the Python server is running
    /// Returns true if server responds to health check, false otherwise
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = regularTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check for HTTP 200 OK
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            // Try to decode the response
            let healthResponse = try decoder.decode(HealthResponse.self, from: data)
            return healthResponse.status == "ok"

        } catch {
            // Any error means server is not reachable
            return false
        }
    }

    /// Get current server status (idle, recording, transcribing)
    func getStatus() async throws -> String {
        guard let url = URL(string: "\(baseURL)/status") else {
            throw PythonBridgeError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = regularTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PythonBridgeError.networkError("Invalid response")
            }

            if httpResponse.statusCode == 200 {
                let statusResponse = try decoder.decode(StatusResponse.self, from: data)
                return statusResponse.status
            } else {
                throw PythonBridgeError.networkError("Server returned \(httpResponse.statusCode)")
            }

        } catch is URLError {
            throw PythonBridgeError.serverOffline
        } catch let error as PythonBridgeError {
            throw error
        } catch {
            throw PythonBridgeError.networkError(error.localizedDescription)
        }
    }

    /// Start recording and transcription
    /// This will wait while the server records audio and transcribes it
    /// - Parameter silenceDuration: How long to wait after speech stops (in seconds)
    /// Returns the transcribed text
    func transcribe(silenceDuration: Double = 1.5) async throws -> String {
        guard let url = URL(string: "\(baseURL)/transcribe") else {
            throw PythonBridgeError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Long timeout because recording + transcription takes time
        request.timeoutInterval = transcriptionTimeout

        // Send the silence duration setting to the server
        let requestBody = TranscribeRequest(silenceDuration: silenceDuration)
        request.httpBody = try JSONEncoder().encode(requestBody)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PythonBridgeError.networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                // Success - decode the transcribed text
                let transcribeResponse = try decoder.decode(TranscribeResponse.self, from: data)
                return transcribeResponse.text

            case 409:
                // Server is busy (already recording or transcribing)
                throw PythonBridgeError.serverBusy

            case 500:
                // Server error
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                    throw PythonBridgeError.transcriptionFailed(errorResponse.detail ?? "Unknown error")
                }
                throw PythonBridgeError.transcriptionFailed("Server error")

            default:
                throw PythonBridgeError.networkError("Unexpected status: \(httpResponse.statusCode)")
            }

        } catch is URLError {
            throw PythonBridgeError.serverOffline
        } catch let error as PythonBridgeError {
            throw error
        } catch {
            throw PythonBridgeError.networkError(error.localizedDescription)
        }
    }
}
