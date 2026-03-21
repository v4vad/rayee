//
//  UpdateManager.swift
//  Rayee
//
//  Manages app updates using the Sparkle framework.
//  Sparkle checks a remote XML file (appcast) for new versions
//  and shows an update dialog when one is available.
//

import Foundation
import Sparkle

/// Wraps Sparkle's updater so the rest of the app can trigger update checks
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    /// Whether an update check can be started right now
    @Published var canCheckForUpdates = false

    private init() {
        // startingUpdater: true means Sparkle will begin automatic
        // background checks as soon as the app launches
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe Sparkle's canCheckForUpdates property so the
        // menu item can enable/disable itself
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Called when the user clicks "Check for Updates..." in the menu
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
