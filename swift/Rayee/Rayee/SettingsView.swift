//
//  SettingsView.swift
//  Rayee
//
//  The Settings window: a sidebar of sections, like System Settings.
//  Used as the body of the Settings scene in RayeeApp.
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case recording
    case smartDictation
    case speechModel
    case dictionary
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .recording: return "Recording"
        case .smartDictation: return "Smart Dictation"
        case .speechModel: return "Speech Model"
        case .dictionary: return "Dictionary"
        case .history: return "History"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .recording: return "waveform"
        case .smartDictation: return "wand.and.sparkles"
        case .speechModel: return "cpu"
        case .dictionary: return "character.book.closed"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }

    /// Section names the app used to deep-link with, plus the new ones
    init?(deepLink: String) {
        switch deepLink {
        case "models": self = .speechModel
        case "transformations": self = .smartDictation
        case "vocabulary": self = .dictionary
        default: self.init(rawValue: deepLink)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            detail
                .navigationTitle((selection ?? .general).title)
        }
        .frame(minWidth: 720, minHeight: 500)
        .onAppear(perform: applyDeepLink)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsSection)) { _ in
            applyDeepLink()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralSettingsTab()
        case .recording: RecordingSettingsTab()
        case .smartDictation: SmartDictationSettingsTab()
        case .speechModel: ModelsSettingsTab()
        case .dictionary: VocabularySettingsTab()
        case .history: HistoryView()
        case .about: AboutSettingsTab()
        }
    }

    /// The menu asks for a section by saving its name; read it once, then forget it.
    private func applyDeepLink() {
        guard let link = UserDefaults.standard.string(forKey: "settingsTab") else { return }
        UserDefaults.standard.removeObject(forKey: "settingsTab")
        if let section = SettingsSection(deepLink: link) { selection = section }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotkeyConfigChanged = Notification.Name("hotkeyConfigChanged")
    static let openSetupGuide = Notification.Name("openSetupGuide")
    static let openSettingsSection = Notification.Name("openSettingsSection")
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
