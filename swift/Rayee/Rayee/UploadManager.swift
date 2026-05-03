//
//  UploadManager.swift
//  Rayee
//
//  Orchestrates the audio file upload flow:
//  1. Open file picker to select an audio file
//  2. Convert it to WAV 16kHz mono using AudioFileConverter
//  3. Transcribe with WhisperKit
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

        // Step 2: Transcribe with WhisperKit
        status = .transcribing

        do {
            let audioData = try AudioFileConverter.loadAudioAsFloat32(url: convertedURL)
            let text = try await WhisperKitManager.shared.transcribe(
                audioBuffer: audioData,
                vocabulary: settings.vocabularyList
            )

            // Step 3: Save result
            if !text.isEmpty {
                let record = UploadRecord(
                    fileName: fileURL.lastPathComponent,
                    text: text,
                    modelUsed: settings.selectedWhisperKitModel
                )
                historyManager.addUpload(record)
            }

            status = .success(text.isEmpty ? "(No speech detected)" : text)
        } catch {
            status = .error(error.localizedDescription)
        }

        // Step 4: Clean up temp file
        AudioFileConverter.cleanupTempFile(convertedURL)
    }
}
