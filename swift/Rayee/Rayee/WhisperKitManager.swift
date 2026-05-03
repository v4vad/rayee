import Foundation
import WhisperKit

@MainActor
class WhisperKitManager: ObservableObject {
    static let shared = WhisperKitManager()

    @Published private(set) var isLoading = false
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?

    private var whisperKit: WhisperKit?
    private var currentModelName: String?

    private init() {}

    // MARK: - Model Loading

    func loadModel(_ modelName: String) async {
        guard modelName != currentModelName || whisperKit == nil else { return }
        isLoading = true
        loadError = nil

        do {
            whisperKit = try await WhisperKit(model: modelName)
            currentModelName = modelName
            isLoaded = true
            AppLogger.log("WhisperKit loaded: \(modelName)", category: "whisper")
        } catch {
            loadError = error.localizedDescription
            isLoaded = false
            AppLogger.log("WhisperKit load failed: \(error)", category: "whisper")
        }

        isLoading = false
    }

    // MARK: - Transcription

    func transcribe(audioBuffer: [Float], vocabulary: [String]) async throws -> String {
        guard let wk = whisperKit else {
            throw WhisperKitError.modelNotLoaded
        }

        var options = DecodingOptions()
        if let prompt = Self.buildVocabularyPrompt(from: vocabulary),
           let tokens = wk.tokenizer?.encode(text: prompt) {
            options = DecodingOptions(promptTokens: tokens)
        }

        let results = try await wk.transcribe(audioArray: audioBuffer, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Helpers

    nonisolated static func buildVocabularyPrompt(from words: [String]) -> String? {
        guard !words.isEmpty else { return nil }
        return words.joined(separator: ", ")
    }
}

enum WhisperKitError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded. Please wait for initialization."
        }
    }
}
