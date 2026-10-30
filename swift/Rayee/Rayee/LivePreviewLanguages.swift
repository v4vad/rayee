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

    /// Keeps only `identifier` reserved with Apple, and downloads its speech data if missing.
    func choose(_ identifier: String) async {
        do {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
                AppLogger.log("Live preview language \(identifier) not supported", category: "live")
                return
            }
            for reserved in await AssetInventory.reservedLocales
            where reserved.identifier(.bcp47) != locale.identifier(.bcp47) {
                await AssetInventory.release(reservedLocale: reserved)
            }
            try await AssetInventory.reserve(locale: locale)

            let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                downloadProgress = 0
                progressObservation = request.progress.observe(\.fractionCompleted) { progress, _ in
                    let fraction = progress.fractionCompleted
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.downloadProgress != nil else { return }
                        self.downloadProgress = fraction
                    }
                }
                defer {
                    progressObservation?.invalidate()
                    progressObservation = nil
                    downloadProgress = nil
                }
                try await request.downloadAndInstall()
            }
        } catch {
            AppLogger.log("Live preview language \(identifier) failed: \(error)", category: "live")
        }
    }
}
