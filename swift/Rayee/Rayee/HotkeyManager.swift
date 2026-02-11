//
//  HotkeyManager.swift
//  Rayee
//
//  Handles global keyboard shortcuts that work from any application.
//  Uses CGEvent tap to listen for key combinations system-wide.
//

import Foundation
import Cocoa
import Carbon.HIToolbox

class HotkeyManager: ObservableObject {
    // Singleton instance
    static let shared = HotkeyManager()

    // Published so UI can react to permission changes
    @Published var isEnabled: Bool = false
    @Published var hasPermission: Bool = false

    // The callback to execute when hotkey is pressed
    var onHotkeyPressed: (() -> Void)?

    // The callback to execute when Escape is pressed (returns true to consume the key)
    var onEscapePressed: (() -> Bool)?

    // Internal state for the event tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {
        // Listen for hotkey configuration changes from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyConfigChanged),
            name: .hotkeyConfigChanged,
            object: nil
        )
    }

    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Check if we have accessibility permission (required for global hotkeys)
    func checkAccessibilityPermission() -> Bool {
        // This will prompt the user if permission hasn't been granted/denied yet
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasPermission = trusted
        return trusted
    }

    /// Check permission without prompting
    func hasAccessibilityPermissionSilent() -> Bool {
        let trusted = AXIsProcessTrusted()
        hasPermission = trusted
        return trusted
    }

    /// Start listening for the global hotkey
    func start() {
        // Check permission first
        guard hasAccessibilityPermissionSilent() else {
            AppLogger.log("Cannot start - no accessibility permission", category: "hotkey")
            isEnabled = false
            return
        }

        // Don't start twice
        guard eventTap == nil else {
            AppLogger.log("Already running", category: "hotkey")
            return
        }

        // Create an event tap that listens for key down events
        // We use a callback that will check if the pressed keys match our hotkey
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // Create the event tap
        // Note: We capture 'self' weakly to avoid retain cycles
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            // Get the HotkeyManager instance from the refcon pointer
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            // Handle the event
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        // Create the tap
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,           // Listen at session level
            place: .headInsertEventTap,        // Insert at head of tap list
            options: .defaultTap,              // Can modify events
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            AppLogger.log("Failed to create event tap", category: "hotkey")
            isEnabled = false
            return
        }

        // Create a run loop source and add it to the current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        guard let runLoopSource = runLoopSource else {
            AppLogger.log("Failed to create run loop source", category: "hotkey")
            self.eventTap = nil
            isEnabled = false
            return
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        // Enable the tap
        CGEvent.tapEnable(tap: eventTap, enable: true)

        isEnabled = true
        AppLogger.log("Started listening for \(SettingsManager.shared.hotkeyConfig.displayString)", category: "hotkey")
    }

    /// Stop listening for the global hotkey
    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isEnabled = false
        print("HotkeyManager: Stopped")
    }

    /// Restart the hotkey listener (useful after changing hotkey configuration)
    func restart() {
        stop()
        start()
    }

    // MARK: - Private Methods

    /// Handle incoming keyboard events
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the tap gets disabled (system can do this), re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // Only process keyDown events
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        // Get the pressed key code
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))

        // Get the pressed modifiers and convert to Carbon format
        let flags = event.flags
        var modifiers: UInt32 = 0

        if flags.contains(.maskControl) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.maskAlternate) {  // Option key
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.maskShift) {
            modifiers |= UInt32(shiftKey)
        }
        if flags.contains(.maskCommand) {
            modifiers |= UInt32(cmdKey)
        }

        // Check if the pressed keys match our configured hotkey
        let config = SettingsManager.shared.hotkeyConfig

        if keyCode == config.keyCode && modifiers == config.modifiers {
            // Hotkey matched! Execute the callback on the main thread
            AppLogger.log("Hotkey matched! keyCode=\(keyCode) modifiers=\(modifiers)", category: "hotkey")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyPressed?()
            }

            // Return nil to consume the event (don't pass it to other apps)
            return nil
        }

        // Check for Escape key (keyCode 53) with no modifiers
        // This allows cancelling recording while letting normal Escape usage pass through
        // Note: We dispatch async and always consume the key when recording to avoid deadlocks
        if keyCode == 53 && modifiers == 0 {
            // Check if we should handle Escape (callback returns true if recording)
            // We use a semaphore with timeout to safely check from the event tap
            let semaphore = DispatchSemaphore(value: 0)
            var shouldConsume = false

            DispatchQueue.main.async { [weak self] in
                shouldConsume = self?.onEscapePressed?() ?? false
                semaphore.signal()
            }

            // Wait briefly for the result (10ms max to avoid blocking)
            let result = semaphore.wait(timeout: .now() + 0.01)
            if result == .success && shouldConsume {
                return nil  // Consume the event (don't pass to other apps)
            }
        }

        // Not our hotkey - let the event pass through
        return Unmanaged.passRetained(event)
    }

    /// Called when the user changes the hotkey in Settings
    @objc private func hotkeyConfigChanged() {
        print("HotkeyManager: Configuration changed to \(SettingsManager.shared.hotkeyConfig.displayString)")
        // Restart to apply the new hotkey
        if isEnabled {
            restart()
        }
    }
}
