//
//  AudioFileConverter.swift
//  Rayee
//
//  Converts any audio format (MP3, M4A, AAC, etc.) to WAV 16kHz mono
//  using AVFoundation. The converted file is saved to a temp directory
//  and should be deleted after use.
//

import AVFoundation
import Foundation

enum AudioFileConverterError: LocalizedError {
    case fileNotFound(String)
    case conversionFailed(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: \(ext)"
        }
    }
}

class AudioFileConverter {

    /// Convert an audio file to WAV 16kHz mono for Whisper transcription.
    /// Returns the path to the converted temp file.
    static func convertToWav(inputURL: URL) async throws -> URL {
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw AudioFileConverterError.fileNotFound(inputURL.path)
        }

        // If it's already a 16kHz mono WAV, just return the original path
        if inputURL.pathExtension.lowercased() == "wav" {
            if let isAlreadyValid = try? checkWavFormat(url: inputURL), isAlreadyValid {
                return inputURL
            }
        }

        // Create output path in temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent("rayee_upload_\(UUID().uuidString).wav")

        // Run conversion on a background thread
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.performConversion(input: inputURL, output: outputURL)
                    continuation.resume(returning: outputURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Clean up a temporary converted file
    static func cleanupTempFile(_ url: URL) {
        // Only delete files in the temp directory to be safe
        if url.path.contains(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Private

    /// Check if a WAV file is already 16kHz mono
    private static func checkWavFormat(url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        return format.sampleRate == Config.audioSampleRate &&
               format.channelCount == 1
    }

    /// Perform the actual audio conversion using AVFoundation
    private static func performConversion(input: URL, output: URL) throws {
        // Open the source audio file
        let sourceFile: AVAudioFile
        do {
            sourceFile = try AVAudioFile(forReading: input)
        } catch {
            throw AudioFileConverterError.conversionFailed(
                "Cannot read audio file: \(error.localizedDescription)"
            )
        }

        // Target format: 16kHz, mono, 16-bit integer (standard WAV for Whisper)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Config.audioSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioFileConverterError.conversionFailed("Cannot create target audio format")
        }

        // Create the output WAV file
        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(
                forWriting: output,
                settings: targetFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw AudioFileConverterError.conversionFailed(
                "Cannot create output file: \(error.localizedDescription)"
            )
        }

        // Set up converter from source format to target format
        guard let converter = AVAudioConverter(
            from: sourceFile.processingFormat,
            to: targetFormat
        ) else {
            throw AudioFileConverterError.conversionFailed(
                "Cannot create audio converter"
            )
        }

        // Process in chunks to keep memory usage low for large files
        let frameCapacity: AVAudioFrameCount = 4096
        guard let convertBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCapacity
        ) else {
            throw AudioFileConverterError.conversionFailed("Cannot create conversion buffer")
        }

        // Read and convert the entire file in chunks
        while true {
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                // Read a chunk from the source file
                guard let readBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFile.processingFormat,
                    frameCapacity: frameCapacity
                ) else {
                    outStatus.pointee = .endOfStream
                    return nil
                }

                do {
                    try sourceFile.read(into: readBuffer)
                    if readBuffer.frameLength == 0 {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return readBuffer
                } catch {
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }

            var conversionError: NSError?
            let status = converter.convert(to: convertBuffer, error: &conversionError, withInputFrom: inputBlock)

            if let conversionError = conversionError {
                throw AudioFileConverterError.conversionFailed(conversionError.localizedDescription)
            }

            if convertBuffer.frameLength == 0 || status == .endOfStream {
                break
            }

            // Write the converted chunk to the output file
            do {
                try outputFile.write(from: convertBuffer)
            } catch {
                throw AudioFileConverterError.conversionFailed(
                    "Cannot write to output file: \(error.localizedDescription)"
                )
            }

            if status == .inputRanDry {
                break
            }
        }
    }
}
