//
//  RecorderController.swift
//  Rayee
//
//  Owns the recorder's window: shows it on the screen with the pointer, springs it between
//  states, closes it on time, and lets clicks through everywhere except the shape itself.
//

import SwiftUI
import AppKit

/// The recorder's window. It takes the keyboard only in the Result state, so the app being dictated into keeps it.
private final class RecorderPanel: NSPanel {
    var allowsKeyFocus = false
    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}

enum RecorderMotion {
    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var change: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.80)
    }

    static var close: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 1.0)
    }
}

final class RecorderController: ObservableObject {
    @Published private(set) var phase: RecorderPhase = .hidden
    @Published private(set) var mode: RecorderLayoutMode = .capsule(gap: 30)
    @Published private(set) var recordingDuration: TimeInterval = 0

    let audioLevelMonitor = AudioLevelMonitor()

    /// A click on the shape, Esc-like buttons (✕)
    var onCommand: ((RecorderCommand) -> Void)?
    var onCopy: ((String) -> Void)?
    var onErrorAction: ((RecorderErrorAction) -> Void)?

    private var panel: RecorderPanel?
    private var screenFrame: CGRect = .zero
    private var recordingTimer: Timer?
    private var dismissWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?
    private var mouseMonitors: [Any] = []
    private var isHovering = false
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.screensChanged()
        }
    }

    // MARK: - Showing and hiding

    func show(_ newPhase: RecorderPhase) {
        guard newPhase != .hidden else { hide(); return }
        orderOutWork?.cancel()
        if phase == .hidden { placeOnCurrentScreen() }

        if newPhase == .listening {
            startTimer()
        } else {
            stopTimer()
        }

        withAnimation(RecorderMotion.change) { phase = newPhase }

        panel?.allowsKeyFocus = newPhase.takesKeyboardFocus
        if newPhase.takesKeyboardFocus { panel?.makeKey() }
        switch newPhase {
        case .pasted, .error:
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        default:
            break
        }
        updateMouseHandling()
        scheduleAutoDismiss()
    }

    func hide() {
        guard phase != .hidden else { return }
        dismissWork?.cancel()
        stopTimer()
        panel?.allowsKeyFocus = false
        withAnimation(RecorderMotion.close) { phase = .hidden }
        updateMouseHandling()

        // Take the window off screen once the close animation is done, unless it reopened meanwhile.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .hidden else { return }
            self.panel?.orderOut(nil)
            self.audioLevelMonitor.reset()
        }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Window

    private func placeOnCurrentScreen() {
        guard let screen = NotchGeometry.currentScreen() else { return }
        let info = ScreenInfo(screen)
        screenFrame = info.frame
        mode = NotchGeometry.mode(for: info, style: SettingsManager.shared.recorderStyle)
        let panel = self.panel ?? makePanel()
        panel.setFrame(
            NotchGeometry.windowFrame(screen: screenFrame, mode: mode, maxBodyHeight: RecorderLayout.maxBodyHeight),
            display: false)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> RecorderPanel {
        let panel = RecorderPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the menu bar, so the shape can sit inside it
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep it out of screen recordings and screen sharing (best effort)
        panel.sharingType = .none
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(rootView: RecorderView(controller: self))
        // The window's size comes from NotchGeometry, not from the SwiftUI content
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func screensChanged() {
        guard phase != .hidden else { return }
        placeOnCurrentScreen()
        updateMouseHandling()
    }

    // MARK: - Clicks and hover

    /// The window is wider than the notch. It takes clicks only while the pointer is over the shape itself.
    private func updateMouseHandling() {
        guard phase != .hidden else {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors = []
            panel?.ignoresMouseEvents = true
            setHovering(false)
            return
        }
        if mouseMonitors.isEmpty {
            let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
                self?.pointerMoved()
            }) {
                mouseMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
                self?.pointerMoved()
                return event
            }) {
                mouseMonitors.append(local)
            }
        }
        pointerMoved()
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        let rects = NotchGeometry.hitRects(
            screen: screenFrame, mode: mode, bodyHeight: RecorderLayout.bodyHeight(for: phase))
        let inside = rects.contains { NotchGeometry.contains($0, point) }
        panel?.ignoresMouseEvents = !inside
        setHovering(inside)
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        scheduleAutoDismiss()
    }

    // MARK: - Timers

    /// (Re)starts the countdown for the current state. Hovering a Result or Error pauses it; leaving restarts it.
    private func scheduleAutoDismiss() {
        dismissWork?.cancel()
        guard let delay = phase.autoDismissDelay else { return }
        if isHovering && phase.hoverPausesDismiss { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startTimer() {
        stopTimer()
        recordingDuration = 0
        audioLevelMonitor.reset()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}
