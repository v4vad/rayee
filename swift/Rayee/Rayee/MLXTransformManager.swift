//
//  MLXTransformManager.swift
//  Rayee
//
//  Manages on-device LLM text transformations via mlx-swift-lm.
//
//  CURRENT STATUS: buildPrompt() is fully implemented. loadModelIfNeeded() and
//  streamTransform() are stubbed — native MLX model loading requires the
//  `swift-transformers` package (HuggingFace hub client + tokenizer loader),
//  which is not yet a project dependency. See ROADMAP.md for the unblocking plan.
//

import Foundation

// MARK: - Error Types

enum MLXTransformError: LocalizedError {
    case modelNotLoaded
    case streamingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "MLX native model loading requires swift-transformers + MLXHuggingFace. See ROADMAP.md."
        case .streamingFailed(let reason):
            return "Streaming failed: \(reason)"
        }
    }
}

// MARK: - Manager

/// Manages on-device LLM text transformations.
///
/// Intended to replace the Python `/transform_stream` endpoint with a
/// fully native MLX Llama 3.2 1B (4-bit) inference path.
///
/// - Note: Model loading is currently stubbed; `swift-transformers` must be
///   added as a Swift Package dependency before the loading path can be activated.
@MainActor
final class MLXTransformManager: ObservableObject {

    static let shared = MLXTransformManager()

    // MARK: Published state

    @Published private(set) var isModelLoaded = false
    @Published private(set) var isModelLoading = false
    @Published private(set) var loadError: String?

    // MARK: Private

    /// HuggingFace model identifier for Llama 3.2 1B 4-bit quantised weights.
    private static let modelID = "mlx-community/Llama-3.2-1B-Instruct-4bit"

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

    // MARK: - Model Loading (stubbed — awaiting swift-transformers dependency)

    /// Loads the MLX model into memory if it is not already loaded.
    ///
    /// - Note: Currently a stub. Full implementation requires:
    ///   1. Add `swift-transformers` SPM dependency.
    ///   2. Enable `MLXHuggingFace` product in Package.swift.
    ///   3. Use `LLMModelFactory.shared.loadContainer(from: hubDownloader, using: tokenizerLoader, configuration:)`.
    func loadModelIfNeeded() async {
        guard !isModelLoaded && !isModelLoading else { return }

        isModelLoading = true
        loadError = "MLX native model loading requires swift-transformers + MLXHuggingFace. See ROADMAP.md."
        AppLogger.log(
            "MLXTransformManager: model loading stubbed — swift-transformers not in project",
            category: "mlx"
        )
        isModelLoading = false
        // isModelLoaded remains false
    }

    /// Unloads the model from memory and cancels the idle timer.
    func unloadModel() {
        unloadTimer?.invalidate()
        unloadTimer = nil
        isModelLoaded = false
        AppLogger.log("MLXTransformManager: model unloaded", category: "mlx")
    }

    // MARK: - Streaming Transforms (stubbed)

    /// Streams transformed text tokens for the given input.
    ///
    /// - Parameters:
    ///   - text: The source text to transform.
    ///   - type: The transformation to apply.
    ///   - onToken: Called for each streamed token string.
    ///
    /// - Throws: `MLXTransformError.modelNotLoaded` until the loading path is activated.
    func streamTransform(
        text: String,
        type transformType: TransformationType,
        onToken: @escaping (String) -> Void
    ) async throws {
        guard isModelLoaded else {
            throw MLXTransformError.modelNotLoaded
        }

        // Full streaming implementation (to be activated once swift-transformers is added):
        //
        //   let (system, user) = Self.buildPrompt(text: text, type: transformType)
        //   let chat: [Chat.Message] = [.system(system), .user(user)]
        //   let userInput = UserInput(chat: chat)
        //   let parameters = GenerateParameters(temperature: 0.3)
        //
        //   for await generation in try await container.generate(input: ..., parameters: parameters) {
        //       if case .chunk(let token) = generation { onToken(token) }
        //   }
        //
        //   resetUnloadTimer()
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
