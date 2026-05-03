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
    case streamingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX native model is not loaded. Please wait."
        case .streamingFailed(let reason):
            return "Streaming failed: \(reason)"
        }
    }
}

// MARK: - Manager

/// Manages on-device LLM text transformations using Llama 3.2 1B (4-bit) via MLX.
@MainActor
final class MLXTransformManager: ObservableObject {

    static let shared = MLXTransformManager()

    // MARK: Published state

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isModelLoading = false
    @Published private(set) var loadError: String?

    // MARK: Private

    private var modelContainer: ModelContainer?

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
        let system = "You are a concise text transformation assistant. Output only the transformed text, no explanations."

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
        }

        return (system: system, user: user)
    }

    // MARK: - Model Loading

    /// Loads the MLX Llama 3.2 1B (4-bit) model if not already loaded.
    func loadModelIfNeeded() async {
        guard modelContainer == nil, !isModelLoading else {
            resetUnloadTimer()
            return
        }

        isModelLoading = true
        loadError = nil

        do {
            let config = LLMRegistry.llama3_2_1B_4bit
            modelContainer = try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: config
            )
            isModelLoaded = true
            AppLogger.log("MLXTransformManager: model loaded", category: "mlx")
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
        isModelLoaded = false
        AppLogger.log("MLXTransformManager: model unloaded (idle timeout)", category: "mlx")
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
        let userInput = UserInput(chat: chat)
        let parameters = GenerateParameters(temperature: 0.0)

        // Prepare input within the container's isolation, then stream generation.
        let lmInput = try await container.prepare(input: userInput)
        let stream = try await container.generate(input: lmInput, parameters: parameters)

        for await generation in stream {
            if case .chunk(let token) = generation {
                onToken(token)
            }
        }
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
