//
//  SetupGuideView.swift
//  Rayee
//
//  A checklist-style view showing the status of each requirement.
//  Appears on first launch and is accessible from the menu bar anytime.
//

import SwiftUI

struct SetupGuideView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var modelManager = WhisperKitModelManager.shared
    @ObservedObject private var transformManager = MLXTransformManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var micPermission = false
    @State private var accessibilityPermission = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    checklistItems
                }
                .padding(24)
            }

            Divider()

            footerView
                .padding(16)
        }
        .frame(width: 480, height: 560)
        .onAppear { refreshStatus() }
        .onReceive(timer) { _ in refreshStatus() }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)

            Text("Welcome to Rayee")
                .font(.title2.bold())

            Text("100% local — your voice never leaves this Mac")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Checklist Items

    private var checklistItems: some View {
        VStack(spacing: 12) {
            // AI Model Status (WhisperKit load state)
            ChecklistRow(
                title: "AI Model",
                status: appState.isWhisperReady ? .ready : (appState.isWhisperLoading ? .optional : .notReady),
                detail: whisperModelDetail,
                actionLabel: (!appState.isWhisperReady && !appState.isWhisperLoading) ? "Load" : nil,
                action: { appState.loadWhisperModel() }
            )

            // Microphone Permission
            ChecklistRow(
                title: "Microphone Permission",
                status: micPermission ? .ready : .notReady,
                detail: micPermission ? "Granted" : "Not granted",
                actionLabel: micPermission ? nil : "Grant",
                action: { requestMicPermission() }
            )

            // Accessibility Permission
            ChecklistRow(
                title: "Accessibility Permission",
                status: accessibilityPermission ? .ready : .notReady,
                detail: accessibilityPermission ? "Granted" : "Not granted",
                actionLabel: accessibilityPermission ? nil : "Open Settings",
                action: { openAccessibilitySettings() }
            )

            // Whisper Model Download
            ChecklistRow(
                title: "Whisper Model",
                status: isSelectedModelDownloaded ? .ready : .notReady,
                detail: isSelectedModelDownloaded ? "Downloaded" : "Not downloaded",
                actionLabel: isSelectedModelDownloaded ? nil : "Download",
                action: { downloadWhisperModel() }
            )

            // Transform Model (optional)
            ChecklistRow(
                title: "Transform Model",
                status: transformManager.isModelLoaded ? .ready : .optional,
                detail: transformModelDetail,
                actionLabel: nil,
                action: {},
                isOptional: true
            )

            Divider()
                .padding(.vertical, 8)

            HotkeyPickerView()
        }
    }

    private var whisperModelDetail: String {
        if appState.isWhisperLoading { return "Loading..." }
        if appState.isWhisperReady { return "Ready" }
        return "Not loaded"
    }

    private var isSelectedModelDownloaded: Bool {
        let targetName = settings.selectedWhisperKitModel
        for model in modelManager.models {
            if model.id == targetName, case .ready = model.status { return true }
        }
        return false
    }

    private var transformModelDetail: String {
        if transformManager.isModelLoading { return "Loading..." }
        if transformManager.isModelLoaded { return "Ready" }
        return "Loads automatically on first use"
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Done") {
                settings.hasCompletedSetup = true
                dismiss()
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Status Refresh

    private func refreshStatus() {
        Task {
            let granted = await AudioRecorder.requestMicrophonePermission()
            await MainActor.run { micPermission = granted }
        }

        accessibilityPermission = PasteManager.shared.hasAccessibilityPermission()

        Task {
            await modelManager.refreshModels()
        }
    }

    // MARK: - Actions

    private func requestMicPermission() {
        Task {
            let granted = await AudioRecorder.requestMicrophonePermission()
            await MainActor.run { micPermission = granted }
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func downloadWhisperModel() {
        modelManager.downloadModel(settings.selectedWhisperKitModel)
    }
}

// MARK: - Checklist Row

enum ChecklistStatus {
    case ready
    case notReady
    case optional
}

struct ChecklistRow: View {
    let title: String
    let status: ChecklistStatus
    let detail: String
    let actionLabel: String?
    let action: () -> Void
    var isOptional: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if isOptional {
                        Text("Optional")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let label = actionLabel {
                Button(label, action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .notReady:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .optional:
            Image(systemName: "circle.dashed")
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SetupGuideView()
        .environmentObject(AppState())
}
