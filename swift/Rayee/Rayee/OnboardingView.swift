//
//  OnboardingView.swift
//  Rayee
//
//  First-run setup, one step per screen: welcome, microphone, accessibility, speech model,
//  then a real dictation into a practice box. Also opened from Settings → About.
//  Spec: docs/superpowers/specs/2026-10-17-design-refresh-design.md §4
//

import SwiftUI
import AVFoundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case speechModel
    case tryIt

    var id: Int { rawValue }
}

struct OnboardingInput: Equatable {
    var microphoneAllowed: Bool
    var accessibilityAllowed: Bool
    var speechModelReady: Bool
}

enum OnboardingRules {
    static func canContinue(_ step: OnboardingStep, _ input: OnboardingInput) -> Bool {
        switch step {
        case .microphone: return input.microphoneAllowed
        case .speechModel: return input.speechModelReady
        case .welcome, .accessibility, .tryIt: return true
        }
    }

    static func continueLabel(_ step: OnboardingStep, _ input: OnboardingInput) -> String {
        switch step {
        case .welcome: return "Get Started"
        case .accessibility: return input.accessibilityAllowed ? "Continue" : "Skip"
        case .tryIt: return "Finish"
        case .microphone, .speechModel: return "Continue"
        }
    }

    static func next(_ step: OnboardingStep) -> OnboardingStep? {
        OnboardingStep(rawValue: step.rawValue + 1)
    }

    static func previous(_ step: OnboardingStep) -> OnboardingStep? {
        OnboardingStep(rawValue: step.rawValue - 1)
    }
}

/// A live microphone level for the "Say something" meter. Runs only while that step is on screen.
final class MicLevelPreview {
    let levels = AudioLevelMonitor(bufferSize: 24)
    private let engine = AVAudioEngine()
    private var running = false

    func start() {
        guard !running, AudioRecorder.hasMicrophonePermission() else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No input device gives a zero format, and installing a tap with it crashes
        guard format.channelCount > 0, format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            self?.levels.addLevel(sqrt(sum / Float(count)))
        }
        do {
            try engine.start()
            running = true
        } catch {
            input.removeTap(onBus: 0)
            AppLogger.log("Microphone preview failed: \(error.localizedDescription)", category: "audio")
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}

/// Holds what the onboarding steps share, so text from the practice dictation can reach the view.
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    @Published var practiceText = ""
    let micPreview = MicLevelPreview()

    func beginPractice() {
        AppState.shared.practiceHandler = { [weak self] text in
            guard let self else { return }
            self.practiceText = self.practiceText.isEmpty ? text : self.practiceText + " " + text
        }
    }

    func endPractice() {
        AppState.shared.practiceHandler = nil
    }
}

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var status = SystemStatusMonitor.shared
    @StateObject private var model = OnboardingModel()
    @Environment(\.dismiss) private var dismiss

    private var input: OnboardingInput {
        OnboardingInput(
            microphoneAllowed: !status.problems.contains(.microphoneOff),
            accessibilityAllowed: !status.problems.contains(.accessibilityOff),
            speechModelReady: appState.isWhisperReady)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .id(model.step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.top, 36)
            footer
                .padding(20)
        }
        .frame(width: 520, height: 560)
        .onAppear {
            status.refresh()
            status.startPolling()
        }
        .onDisappear {
            status.stopPolling()
            model.micPreview.stop()
            model.endPractice()
        }
        .onChange(of: model.step) { old, new in stepChanged(from: old, to: new) }
        .onChange(of: input.microphoneAllowed) { _, allowed in
            if allowed && model.step == .microphone { model.micPreview.start() }
        }
        .onChange(of: input.accessibilityAllowed) { _, allowed in
            if allowed && model.step == .accessibility { go(to: OnboardingRules.next(.accessibility)) }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Back") { go(to: OnboardingRules.previous(model.step)) }
                .opacity(model.step == .welcome ? 0 : 1)
                .disabled(model.step == .welcome)
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { step in
                    Circle()
                        .fill(step == model.step ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            Button(OnboardingRules.continueLabel(model.step, input)) { primaryAction() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!OnboardingRules.canContinue(model.step, input))
        }
    }

    private func primaryAction() {
        if model.step == .tryIt {
            settings.hasCompletedSetup = true
            dismiss()
        } else {
            go(to: OnboardingRules.next(model.step))
        }
    }

    private func go(to step: OnboardingStep?) {
        guard let step else { return }
        withAnimation(.snappy(duration: 0.3)) { model.step = step }
    }

    private func stepChanged(from old: OnboardingStep, to new: OnboardingStep) {
        if old == .microphone { model.micPreview.stop() }
        if old == .tryIt { model.endPractice() }
        if new == .microphone { model.micPreview.start() }
        if new == .tryIt { model.beginPractice() }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: welcome
        case .microphone: microphone
        case .accessibility: accessibility
        case .speechModel: speechModel
        case .tryIt: tryIt
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Talk, and Rayee types.")
                .font(.largeTitle.bold())
            Text("Press a shortcut, speak, and your words appear in the app you're using. Everything stays on this Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var microphone: some View {
        StepLayout(icon: "mic.fill", title: "Allow the microphone",
                   message: "Rayee listens only while you're recording.") {
            if input.microphoneAllowed {
                VStack(spacing: 10) {
                    LevelBars(monitor: model.micPreview.levels, barWidth: 4, maxHeight: 40)
                        .padding(14)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                    Text("Say something — the bars should move.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Allow Microphone") { status.fix(.microphoneOff) }
                    .controlSize(.large)
            }
        }
    }

    private var accessibility: some View {
        StepLayout(icon: "hand.raised.fill", title: "Allow Accessibility",
                   message: "So Rayee can paste into your apps and hear your shortcut from anywhere.") {
            if input.accessibilityAllowed {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") { status.fix(.accessibilityOff) }
                        .controlSize(.large)
                    Text("Turn on Rayee in the list, then come back here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var speechModel: some View {
        let size = WhisperModelCatalog.estimatedSizeMB(for: settings.selectedWhisperKitModel)
        return StepLayout(icon: "cpu", title: "Getting the speech model",
                          message: "Rayee turns speech into text on this Mac. The first download is about \(size) MB.") {
            if appState.isWhisperReady {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if appState.isWhisperLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Downloading and preparing… this can take a few minutes the first time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                Button("Download") { appState.loadWhisperModel() }
                    .controlSize(.large)
            }
        }
    }

    private var tryIt: some View {
        StepLayout(icon: "waveform", title: "Try it",
                   message: "Press \(settings.hotkeyConfig.displayString) and say \"Hello Rayee\". Press it again to stop.") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Your words appear here", text: $model.practiceText, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.roundedBorder)
                if !model.practiceText.isEmpty {
                    Label("It works!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if !input.accessibilityAllowed {
                    Label("Your shortcut won't work until Accessibility is allowed. You can allow it later in Settings.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Divider()
                HotkeyPickerView()
                Toggle("Clean up my dictation (Smart Dictation)", isOn: $settings.smartDictationEnabled)
                    .toggleStyle(.switch)
            }
        }
    }
}

/// Icon, title and one-line reason at the top, the step's controls below.
private struct StepLayout<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.top, 20)
            Text(title)
                .font(.title.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer().frame(height: 12)
            content
            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState.shared)
}
