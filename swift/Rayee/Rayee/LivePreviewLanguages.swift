//
//  LivePreviewLanguages.swift
//  Rayee
//
//  The languages Apple's recognizer can show live words in, and the work of
//  reserving and downloading one. Used by Settings → Recording. Failures are logged, never shown.
//

import Foundation
import Speech

struct LanguageOption: Identifiable, Equatable {
    let id: String   // BCP-47, e.g. "en-IN"
    let name: String // e.g. "English (India)"
}

@MainActor
final class LivePreviewLanguages: ObservableObject {
    static let defaultIdentifier = "en-IN"

    @Published private(set) var options: [LanguageOption] = []
    @Published private(set) var isAvailable = true
    /// nil: not downloading. 0: started, but Apple reports no progress yet.
    @Published private(set) var downloadProgress: Double?
    /// True once `load()` has filled `options`
    @Published private(set) var hasLoaded = false

    private var progressObservation: NSKeyValueObservation?

    /// Sorted by the language's name in `displayLocale`
    nonisolated static func sortedOptions(_ identifiers: [String], displayLocale: Locale) -> [LanguageOption] {
        identifiers
            .map { LanguageOption(id: $0, name: displayLocale.localizedString(forIdentifier: $0) ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func load() async {
        let available = SpeechTranscriber.isAvailable
        let supported = await SpeechTranscriber.supportedLocales
        let identifiers = Array(Set(supported.map { $0.identifier(.bcp47) }))
        isAvailable = available
        options = Self.sortedOptions(identifiers, displayLocale: .current)
        hasLoaded = true
    }

    /// Keeps only the latest `identifier` reserved with Apple, and downloads its speech data if missing.
    /// Starts the work and returns; a newer pick cancels the one before it. The work belongs to the
    /// model, so leaving the Settings tab doesn't stop a first-time download.
    func choose(_ identifier: String) {
        currentTask?.cancel()
        generation += 1
        let mine = generation
        currentTask = Task { [weak self] in
            await self?.perform(identifier, generation: mine)
        }
    }

    private var currentTask: Task<Void, Never>?
    /// Bumped on every pick; a task whose number is out of date has been superseded
    private var generation = 0

    private func isLatest(_ mine: Int) -> Bool {
        mine == generation && !Task.isCancelled
    }

    private func perform(_ identifier: String, generation mine: Int) async {
        var ownsProgress = false
        defer {
            if ownsProgress && mine == generation {
                progressObservation?.invalidate()
                progressObservation = nil
                downloadProgress = nil
            }
        }
        do {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
                AppLogger.log("Live preview language \(identifier) not supported", category: "live")
                return
            }
            guard isLatest(mine) else { return }
            for reserved in await AssetInventory.reservedLocales
            where reserved.identifier(.bcp47) != locale.identifier(.bcp47) {
                await AssetInventory.release(reservedLocale: reserved)
            }
            guard isLatest(mine) else { return }
            try await AssetInventory.reserve(locale: locale)
            guard isLatest(mine) else {
                // Superseded while reserving: give this one back (the newer pick released the rest earlier)
                await AssetInventory.release(reservedLocale: locale)
                return
            }

            let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                guard isLatest(mine) else { return }
                ownsProgress = true
                downloadProgress = 0
                progressObservation?.invalidate()
                progressObservation = request.progress.observe(\.fractionCompleted) { progress, _ in
                    let fraction = progress.fractionCompleted
                    DispatchQueue.main.async { [weak self] in
                        guard let self, mine == self.generation, self.downloadProgress != nil else { return }
                        self.downloadProgress = fraction
                    }
                }
                try await request.downloadAndInstall()
            }
        } catch {
            if isLatest(mine) {
                AppLogger.log("Live preview language \(identifier) failed: \(error)", category: "live")
            }
        }
    }
}
