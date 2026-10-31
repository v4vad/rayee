//
//  UpdateManager.swift
//  Rayee
//
//  Manages app updates using the Sparkle framework.
//  Sparkle checks a remote XML file (appcast) for new versions, downloads them in the
//  background, and Rayee installs them by itself once it has been idle for a while.
//

import Foundation
import Sparkle

/// When a downloaded update may be installed. Installing relaunches Rayee, so it waits until
/// nothing is being recorded, transcribed or cleaned up, and the user has been quiet for a bit.
enum UpdateInstallPolicy {
    /// How long Rayee must have been idle before it restarts to update
    static let quietPeriod: TimeInterval = 120

    static func canInstallNow(isBusy: Bool, lastActivity: Date?, now: Date) -> Bool {
        guard !isBusy else { return false }
        guard let lastActivity else { return true }
        return now.timeIntervalSince(lastActivity) >= quietPeriod
    }
}

/// Wraps Sparkle's updater so the rest of the app can trigger update checks
class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController!

    /// Whether an update check can be started right now
    @Published var canCheckForUpdates = false

    /// Installs the downloaded update and relaunches Rayee (set once an update is ready)
    private var installUpdate: (() -> Void)?
    private var installTimer: Timer?

    private override init() {
        super.init()
        // startingUpdater: true means Sparkle will begin automatic
        // background checks as soon as the app launches
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
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

    // MARK: - Installing by itself

    /// Sparkle downloaded an update in the background and would install it when Rayee quits.
    /// Rayee rarely quits, so take over: install as soon as Rayee is idle.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        AppLogger.log("Update \(item.displayVersionString) downloaded; installing when idle", category: "update")
        installUpdate = immediateInstallHandler
        installWhenIdle()
        return true
    }

    /// Installs now if Rayee is idle, otherwise looks again every minute.
    private func installWhenIdle() {
        installTimer?.invalidate()
        installTimer = nil
        guard let installUpdate else { return }

        let appState = AppState.shared
        if UpdateInstallPolicy.canInstallNow(
            isBusy: appState.isBusy, lastActivity: appState.lastActivity, now: Date()
        ) {
            AppLogger.log("Installing update and relaunching", category: "update")
            installUpdate()
        } else {
            installTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                self?.installWhenIdle()
            }
        }
    }
}
