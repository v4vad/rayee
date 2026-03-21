//
//  MenuBarController.swift
//  Rayee
//
//  AppKit-based menu bar controller using NSStatusItem.
//  Replaces SwiftUI MenuBarExtra for better compatibility with
//  menu bar manager apps like Bartender.
//

import AppKit
import SwiftUI
import Combine

/// Manages the menu bar icon and dropdown menu using NSStatusItem
class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    /// Bridge for opening SwiftUI windows from AppKit
    private var openWindowAction: ((String) -> Void)?
    private var bridgeWindow: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        observeStateChanges()
        setupWindowBridge()
        checkFirstLaunch()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            updateIcon()
            button.target = self
            AppLogger.log("Status item created — image: \(button.image != nil ? "loaded" : "NIL"), title: '\(button.title)', frame: \(button.frame)", category: "menubar")
        } else {
            AppLogger.log("WARNING: Status item button is nil!", category: "menubar")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

        // Force the status item to be visible (counteracts Bartender hiding)
        statusItem?.isVisible = true
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        guard let button = statusItem?.button else { return }

        let iconName = appState.menuBarIcon
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Rayee") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            // Fallback if SF Symbol fails to load — keep the icon visible
            button.image = nil
            button.title = "R"
        }
    }

    private func observeStateChanges() {
        appState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$isServerOnline
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    // MARK: - Menu Building (called before each show)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Record / Stop Recording
        let recordItem = NSMenuItem(
            title: recordButtonTitle,
            action: canRecord ? #selector(toggleRecording) : nil,
            keyEquivalent: ""
        )
        recordItem.target = self
        recordItem.isEnabled = canRecord
        menu.addItem(recordItem)

        menu.addItem(.separator())

        // Vocabulary
        let vocabItem = NSMenuItem(title: "Vocabulary...", action: #selector(openVocabulary), keyEquivalent: "")
        vocabItem.target = self
        menu.addItem(vocabItem)

        // History
        let historyItem = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        // Upload Audio
        let uploadItem = NSMenuItem(title: "Upload Audio...", action: #selector(openUploads), keyEquivalent: "")
        uploadItem.target = self
        menu.addItem(uploadItem)

        menu.addItem(.separator())

        // System Status
        let statusItem = NSMenuItem(title: "System Status...", action: #selector(openSystemStatus), keyEquivalent: "")
        statusItem.target = self
        menu.addItem(statusItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = UpdateManager.shared.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Rayee", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func toggleRecording() {
        if appState.status == .recording {
            appState.stopRecording()
        } else {
            appState.startTranscription(autoPaste: true)
        }
    }

    @objc private func openVocabulary() {
        openSettingsWindow(tab: "vocabulary")
    }

    @objc private func openHistory() {
        openSettingsWindow(tab: "history")
    }

    @objc private func openUploads() {
        openSettingsWindow(tab: "uploads")
    }

    @objc private func openSystemStatus() {
        openWindowAction?("setup-guide")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        openSettingsWindow(tab: nil)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func openSettingsWindow(tab: String?) {
        if let tab = tab {
            UserDefaults.standard.set(tab, forKey: "settingsTab")
        }
        openWindowAction?("settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - Computed Properties

    private var recordButtonTitle: String {
        switch appState.status {
        case .startingServer: return "Starting server..."
        case .downloadingModels: return "Downloading models..."
        case .ready, .error: return "Record"
        case .recording: return "Stop Recording"
        case .transcribing: return "Transcribing..."
        }
    }

    private var canRecord: Bool {
        switch appState.status {
        case .ready, .error, .recording: return true
        case .startingServer, .downloadingModels, .transcribing: return false
        }
    }

    // MARK: - Window Bridge

    /// Creates a tiny hidden SwiftUI window that captures @Environment(\.openWindow)
    /// and stores it as a callback. Same proven pattern as RecordingPanelHostView.
    private func setupWindowBridge() {
        let bridgeView = WindowBridgeView { [weak self] action in
            self?.openWindowAction = action
        }

        let hostingView = NSHostingView(rootView: bridgeView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 0, height: 0)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.orderOut(nil)
        bridgeWindow = window
    }

    // MARK: - First Launch

    private func checkFirstLaunch() {
        if !SettingsManager.shared.hasCompletedSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openWindowAction?("setup-guide")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - Window Bridge SwiftUI View

/// A zero-size SwiftUI view that captures the openWindow environment action
/// and passes it back to the AppKit controller via a callback.
private struct WindowBridgeView: View {
    let onOpenWindowAvailable: (@escaping (String) -> Void) -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                onOpenWindowAvailable { windowID in
                    openWindow(id: windowID)
                }
            }
    }
}
