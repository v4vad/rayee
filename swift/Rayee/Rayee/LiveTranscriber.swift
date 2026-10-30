//
//  LiveTranscriber.swift
//  Rayee
//
//  Shows draft words while the user speaks, using Apple's on-device SpeechAnalyzer.
//  Preview only: the pasted text still comes from WhisperKit. Failures are logged, never shown.
//

import Foundation
import AVFoundation
import Speech

/// Decides whether the live preview can run, so the rule can be tested without Apple's speech assets.
enum LivePreviewGate {
    static func shouldRun(isAvailable: Bool, supportedLocale: Locale?, installed: Bool) -> Bool {
        isAvailable && supportedLocale != nil && installed
    }
}

final class LiveTranscriber: @unchecked Sendable {
    /// Always called on the main thread, and never after `stop()`
    var onTranscript: ((LiveTranscript) -> Void)?

    private let languageIdentifier: String

    private let rawStream: AsyncStream<AVAudioPCMBuffer>
    private let rawContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    // Guarded by `lock`
    private let lock = NSLock()
    private var isStopped = false
    private var hasStarted = false
    private var setupTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?

    init(languageIdentifier: String) {
        self.languageIdentifier = languageIdentifier
        // About 60 s of 100 ms buffers, so a stalled recognizer can't grow memory without limit
        (rawStream, rawContinuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(600))
    }

    /// Returns immediately; the setup runs in a task.
    func start() {
        lock.lock()
        guard !isStopped, !hasStarted else { lock.unlock(); return }
        hasStarted = true
        setupTask = Task { [weak self] in
            await self?.run()
        }
        lock.unlock()
    }

    /// Thread-safe and never blocks. Audio sent before setup finishes is held by the stream.
    func append(_ buffer: AVAudioPCMBuffer) {
        rawContinuation.yield(buffer)
    }

    /// Fire-and-forget and idempotent.
    func stop() {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        isStopped = true
        let setup = setupTask
        let results = resultsTask
        let analyzer = analyzer
        setupTask = nil
        resultsTask = nil
        self.analyzer = nil
        lock.unlock()

        rawContinuation.finish()
        setup?.cancel()
        results?.cancel()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    // MARK: - Setup

    private var stopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return isStopped
    }

    private func run() async {
        do {
            guard !stopped else { return }

            let supported = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: languageIdentifier))
            guard let locale = supported else {
                AppLogger.log("Live preview off: language \(languageIdentifier) not supported", category: "live")
                stop()
                return
            }
            let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            let modules: [any SpeechModule] = [transcriber]

            // The preview never starts a download
            let installed = await AssetInventory.status(forModules: modules) == .installed
            guard LivePreviewGate.shouldRun(
                isAvailable: SpeechTranscriber.isAvailable, supportedLocale: supported, installed: installed
            ) else {
                AppLogger.log("Live preview off: speech assets not ready for \(languageIdentifier)", category: "live")
                stop()
                return
            }

            guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules),
                  let sourceFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                AppLogger.log("Live preview off: no usable audio format", category: "live")
                stop()
                return
            }

            let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            let analyzer = SpeechAnalyzer(modules: modules)

            lock.lock()
            if isStopped {
                lock.unlock()
                inputContinuation.finish()
                return
            }
            self.analyzer = analyzer
            lock.unlock()

            try await analyzer.prepareToAnalyze(in: targetFormat)

            let results = Task { [weak self] in
                var transcript = LiveTranscript()
                do {
                    for try await result in transcriber.results {
                        transcript.apply(String(result.text.characters), isFinal: result.isFinal)
                        self?.deliver(transcript)
                    }
                } catch {
                    self?.fail(error)
                }
            }
            lock.lock()
            if isStopped {
                lock.unlock()
                results.cancel()
                inputContinuation.finish()
                await analyzer.cancelAndFinishNow()
                return
            }
            resultsTask = results
            lock.unlock()

            try await analyzer.start(inputSequence: inputStream)

            for await buffer in rawStream {
                if let converted = Self.convertForAnalyzer(buffer, using: converter, to: targetFormat) {
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
            }
            inputContinuation.finish()
        } catch {
            fail(error)
        }
    }

    private func deliver(_ transcript: LiveTranscript) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.onTranscript?(transcript)
        }
    }

    private func fail(_ error: Error) {
        if !stopped {
            let text = "\(error)".lowercased()
            if text.contains("authoriz") || text.contains("permission") {
                AppLogger.log("Live preview needs speech-recognition permission", category: "live")
            } else {
                AppLogger.log("Live preview off: \(error)", category: "live")
            }
        }
        stop()
    }
}

extension LiveTranscriber {
    /// Converts a Rayee buffer (16 kHz mono Float32) to the format Apple's recognizer needs.
    static func convertForAnalyzer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        AudioRecorder.convert(buffer, using: converter, to: format)
    }
}
