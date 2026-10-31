//
//  SystemStatus.swift
//  Rayee
//
//  What stops Rayee from working, and links to where the user fixes it.
//

import AppKit
import AVFoundation
import Combine

/// Pages in System Settings that Rayee sends the user to.
enum SystemSettingsLink {
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// What Privacy & Security calls the list that lets Rayee paste and hear its shortcut.
    /// macOS 27 renamed "Accessibility" to "Device Control and Data Access".
    static func accessibilityName(macOSMajor: Int) -> String {
        macOSMajor >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    static var accessibilityName: String {
        accessibilityName(macOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Something that stops Rayee from working fully.
enum SystemProblem: String, Identifiable, Equatable {
    case microphoneOff
    case speechModelNotLoaded
    case accessibilityOff
    case speechModelLoading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphoneOff: return "Microphone is off"
        case .speechModelNotLoaded: return "Speech model isn't loaded"
        case .accessibilityOff: return "\(SystemSettingsLink.accessibilityName) is off"
        case .speechModelLoading: return "Speech model is loading…"
        }
    }

    /// One more line for the Settings card
    var detail: String? {
        switch self {
        case .microphoneOff: return "Rayee can't hear you."
        case .speechModelNotLoaded: return "Rayee can't turn speech into text yet."
        case .accessibilityOff: return "Turn on Rayee in Privacy & Security so it can paste and hear your shortcut."
        case .speechModelLoading: return nil
        }
    }

    /// The fix button's text, or nil when there's nothing to do but wait
    var fixLabel: String? {
        switch self {
        case .microphoneOff: return "Allow"
        case .speechModelNotLoaded: return "Load"
        case .accessibilityOff: return "Open Settings"
        case .speechModelLoading: return nil
        }
    }

    /// Loading fixes itself, so the menu doesn't warn about it
    var isBlocking: Bool { self != .speechModelLoading }
}

struct SystemStatusInput: Equatable {
    var microphoneAllowed: Bool
    var accessibilityAllowed: Bool
    var speechModelReady: Bool
    var speechModelLoading: Bool
}

enum SystemStatus {
    /// What's wrong, most important first.
    static func problems(_ input: SystemStatusInput) -> [SystemProblem] {
        var problems: [SystemProblem] = []
        if !input.microphoneAllowed { problems.append(.microphoneOff) }
        if !input.speechModelReady && !input.speechModelLoading { problems.append(.speechModelNotLoaded) }
        if !input.accessibilityAllowed { problems.append(.accessibilityOff) }
        if !input.speechModelReady && input.speechModelLoading { problems.append(.speechModelLoading) }
        return problems
    }
}

/// Keeps the problem list current for the Settings card, the menu and onboarding.
/// The checks don't prompt the user. macOS doesn't announce permission changes, so screens that
/// let the user fix a permission poll while they're open.
final class SystemStatusMonitor: ObservableObject {
    static let shared = SystemStatusMonitor()

    @Published private(set) var problems: [SystemProblem] = []

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var pollers = 0

    private init() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        AppState.shared.$isWhisperReady
            .combineLatest(AppState.shared.$isWhisperLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        let input = SystemStatusInput(
            microphoneAllowed: AudioRecorder.hasMicrophonePermission(),
            accessibilityAllowed: PasteManager.shared.hasAccessibilityPermission(),
            speechModelReady: AppState.shared.isWhisperReady,
            speechModelLoading: AppState.shared.isWhisperLoading)
        let latest = SystemStatus.problems(input)
        if latest != problems { problems = latest }
    }

    /// Call from onAppear; pair with stopPolling in onDisappear.
    func startPolling() {
        pollers += 1
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        pollers = max(0, pollers - 1)
        guard pollers == 0 else { return }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func fix(_ problem: SystemProblem) {
        switch problem {
        case .microphoneOff:
            // The first time, macOS asks; after a "Don't Allow" only System Settings can change it.
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                Task {
                    _ = await AudioRecorder.requestMicrophonePermission()
                    await MainActor.run { self.refresh() }
                }
            } else {
                SystemSettingsLink.open(SystemSettingsLink.microphone)
            }
        case .speechModelNotLoaded:
            AppState.shared.loadWhisperModel()
        case .accessibilityOff:
            SystemSettingsLink.open(SystemSettingsLink.accessibility)
        case .speechModelLoading:
            break
        }
    }
}
