//
//  UploadManager.swift
//  Rayee
//
//  Orchestrates the audio file upload flow:
//  1. Open file picker to select an audio file
//  2. Convert it to WAV 16kHz mono using AudioFileConverter
//  3. Send to the Python server for transcription
//  4. Save result to UploadHistoryManager
//
//  This is a singleton so transcription continues even if the Settings window is closed.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Tracks the current state of an upload
enum UploadStatus: Equatable {
    case idle
    case converting
    case transcribing
    case success(String)
    case error(String)
}

class UploadManager: ObservableObject {
    static let shared = UploadManager()

    @Published var status: UploadStatus = .idle
    @Published var currentFileName: String?

    private let pythonBridge = PythonBridge()
    private let historyManager = UploadHistoryManager.shared
    private let settings = SettingsManager.shared

    private init() {}

    // MARK: - Public Methods

    /// Show the file picker and start the upload flow
    func pickAndUploadFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Audio File"
        panel.allowedContentTypes = Config.allowedAudioExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        startUpload(fileURL: url)
    }

    /// Start the upload and transcription flow for a given file
    func startUpload(fileURL: URL) {
        guard status == .idle || isFinished else {
            return
        }

        currentFileName = fileURL.lastPathComponent

        Task { @MainActor in
            await processFile(fileURL: fileURL)
        }
    }

    /// Reset status back to idle (e.g. after user dismisses result)
    func reset() {
        status = .idle
        currentFileName = nil
    }

    // MARK: - Private Methods

    private var isFinished: Bool {
        switch status {
        case .success, .error: return true
        default: return false
        }
    }

    @MainActor
    private func processFile(fileURL: URL) async {
        status = .converting

        // Step 1: Convert to WAV 16kHz mono
        let convertedURL: URL
        do {
            convertedURL = try await AudioFileConverter.convertToWav(inputURL: fileURL)
        } catch {
            status = .error("Conversion failed: \(error.localizedDescription)")
            return
        }

        // Step 2: Send to Python server for transcription
        status = .transcribing

        do {
            let text: String
            if settings.backgroundUploadEnabled {
                // Background mode: uses /transcribe_upload (doesn't block recording)
                text = try await pythonBridge.transcribeUploadedFile(audioPath: convertedURL)
            } else {
                // Blocking mode: uses /transcribe_file (blocks recording)
                text = try await pythonBridge.transcribeUploadedFileBlocking(audioPath: convertedURL)
            }

            // Step 3: Save result
            if !text.isEmpty {
                let record = UploadRecord(
                    fileName: fileURL.lastPathComponent,
                    text: text,
                    modelUsed: settings.selectedModel.rawValue
                )
                historyManager.addUpload(record)
            }

            status = .success(text.isEmpty ? "(No speech detected)" : text)
        } catch {
            let message: String
            if let bridgeError = error as? PythonBridgeError {
                switch bridgeError {
                case .serverBusy:
                    message = "Server is busy with another task. Please wait."
                case .serverOffline:
                    message = "Server is not running."
                case .serverStarting:
                    message = "AI models are still loading. Please wait."
                default:
                    message = bridgeError.localizedDescription
                }
            } else {
                message = error.localizedDescription
            }
            status = .error(message)
        }

        // Step 4: Clean up temp file
        AudioFileConverter.cleanupTempFile(convertedURL)
    }
}
