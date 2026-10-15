//
//  MLXTransformManager.swift
//  Rayee
//
//  Manages on-device LLM text transformations via mlx-swift-lm.
//

import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

// MARK: - Error Types

enum MLXTransformError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "The writing model is not loaded."
        }
    }
}

// MARK: - Model Choice

/// The on-device text models the user can choose from (Settings → Transforms).
enum TransformModel: String, CaseIterable, Identifiable {
    case llama3_2_1B
    case qwen3_1_7B
    case qwen3_4B

    /// Used for new installs and for any saved value this version doesn't recognise.
    static let defaultModel: TransformModel = .llama3_2_1B

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .llama3_2_1B: return "Llama 3.2 1B (fastest)"
        case .qwen3_1_7B: return "Qwen3 1.7B (better writing)"
        case .qwen3_4B: return "Qwen3 4B (best, needs more memory)"
        }
    }

    var approximateDownload: String {
        switch self {
        case .llama3_2_1B: return "about 0.7 GB"
        case .qwen3_1_7B: return "about 1 GB"
        case .qwen3_4B: return "about 2.3 GB"
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .llama3_2_1B: return LLMRegistry.llama3_2_1B_4bit
        case .qwen3_1_7B: return LLMRegistry.qwen3_1_7b_4bit
        case .qwen3_4B: return LLMRegistry.qwen3_4b_4bit
        }
    }

    /// Extra values for the model's chat template. Qwen3 writes out its "thinking"
    /// before answering unless the template is told not to.
    var additionalContext: [String: any Sendable]? {
        switch self {
        case .llama3_2_1B: return nil
        case .qwen3_1_7B, .qwen3_4B: return ["enable_thinking": false]
        }
    }

    static func from(savedValue: String?) -> TransformModel {
        savedValue.flatMap(TransformModel.init(rawValue:)) ?? defaultModel
    }
}

// MARK: - Manager

/// Manages on-device LLM text transformations via MLX, using the model chosen in Settings → Transforms.
@MainActor
final class MLXTransformManager: ObservableObject {

    static let shared = MLXTransformManager()

    // MARK: Published state

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isModelLoading = false
    @Published private(set) var loadError: String?

    // MARK: Private

    private var modelContainer: ModelContainer?

    /// Which model `modelContainer` holds, so a change in Settings triggers a reload.
    private var loadedModel: TransformModel?

    /// Idle timer — unloads model after 30 seconds of inactivity.
    private var unloadTimer: Timer?
    private static let unloadDelay: TimeInterval = 30

    private init() {}

    // MARK: - Prompt Construction (nonisolated — testable without actor hop)

    /// Builds the (system, user) prompt pair for a given transformation type.
    ///
    /// Returns a tuple of `(systemPrompt, userPrompt)` suitable for chat-format
    /// inference. The user prompt embeds `text` and a directive matching `type`.
    nonisolated static func buildPrompt(
        text: String, type transformType: TransformationType
    ) -> (system: String, user: String) {
        var system = "You are a concise text transformation assistant. Output only the transformed text, no explanations."

        let user: String
        switch transformType {
        case .grammar:
            user = "Fix the grammar and spelling of the following text. Output only the corrected text.\n\nText: \(text)"
        case .bullets:
            user = "Convert the following text into a concise bullet point list. Output only the bullet points.\n\nText: \(text)"
        case .rephrase:
            user = "Rephrase the following text to make it clearer and more natural. Output only the rephrased text.\n\nText: \(text)"
        case .formal:
            user = "Rewrite the following text in a formal, professional tone. Output only the formal version.\n\nText: \(text)"
        case .casual:
            user = "Rewrite the following text in a friendly, casual tone. Output only the casual version.\n\nText: \(text)"
        case .smartDictation:
            system = "You are a voice dictation processor. Receive raw speech and output only the final clean text. No explanations."
            user = """
                Clean up this dictated speech:
                - Fix grammar, punctuation, and sentence structure
                - Remove filler words (uh, um, like, you know)
                - Convert spoken punctuation to symbols ("comma" → ,  "period" → .  "new paragraph" → paragraph break)
                - Preserve the speaker's words and meaning exactly — do not rephrase, summarize, or add content
                Output only the cleaned text, nothing else.

                Text: \(text)
                """
        }

        return (system: system, user: user)
    }

    // MARK: - Model Loading

    /// Loads the text model chosen in Settings, if it isn't loaded already.
    /// If a different model is loaded, unloads it first.
    func loadModelIfNeeded() async {
        let wanted = TransformModel.from(savedValue: SettingsManager.shared.transformModel)
        if modelContainer != nil, loadedModel != wanted, !isModelLoading {
            unloadModel()
        }

        guard modelContainer == nil, !isModelLoading else {
            resetUnloadTimer()
            return
        }

        isModelLoading = true
        loadError = nil

        do {
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: wanted.configuration
            )
            loadedModel = wanted
            isModelLoaded = true
            AppLogger.log("MLXTransformManager: model loaded (\(wanted.rawValue))", category: "mlx")
            resetUnloadTimer()
        } catch {
            loadError = error.localizedDescription
            AppLogger.log(
                "MLXTransformManager: model load failed: \(error)", category: "mlx")
        }

        isModelLoading = false
    }

    /// Unloads the model from memory and cancels the idle timer.
    func unloadModel() {
        unloadTimer?.invalidate()
        unloadTimer = nil
        modelContainer = nil
        loadedModel = nil
        isModelLoaded = false
        AppLogger.log("MLXTransformManager: model unloaded", category: "mlx")
    }

    // MARK: - Streaming Transforms

    /// Streams transformed text tokens for the given input.
    ///
    /// - Parameters:
    ///   - text: The source text to transform.
    ///   - type: The transformation to apply.
    ///   - onToken: Called on the main actor for each streamed text chunk.
    ///
    /// - Throws: `MLXTransformError.modelNotLoaded` if the model could not be loaded.
    func streamTransform(
        text: String,
        type transformType: TransformationType,
        onToken: @escaping (String) -> Void
    ) async throws {
        await loadModelIfNeeded()

        guard let container = modelContainer else {
            throw MLXTransformError.modelNotLoaded
        }

        resetUnloadTimer()

        let (systemPrompt, userPrompt) = Self.buildPrompt(text: text, type: transformType)
        let chat: [Chat.Message] = [
            .system(systemPrompt),
            .user(userPrompt),
        ]
        let userInput = UserInput(chat: chat, additionalContext: loadedModel?.additionalContext)
        let parameters = GenerateParameters(temperature: 0.0)

        // Prepare input within the container's isolation, then stream generation.
        let lmInput = try await container.prepare(input: userInput)
        let stream = try await container.generate(input: lmInput, parameters: parameters)

        for await generation in stream {
            try Task.checkCancellation()
            if case .chunk(let token) = generation {
                onToken(token)
            }
        }
        // The stream also ends early when the task is cancelled. Report that as a cancellation, not a result.
        try Task.checkCancellation()
    }

    // MARK: - Private helpers

    private func resetUnloadTimer() {
        unloadTimer?.invalidate()
        unloadTimer = Timer.scheduledTimer(
            withTimeInterval: Self.unloadDelay, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.unloadModel() }
        }
    }
}
