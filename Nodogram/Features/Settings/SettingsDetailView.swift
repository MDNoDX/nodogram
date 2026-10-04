//  Settings, right column: the open page, centred like Telegram's.

import SwiftUI
import NodogramDomain
import NodogramUI

struct SettingsDetailView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.settingsPage {
            case .profile: ProfilePage(model: model)
            case .general: GeneralPage()
            case .notifications: NotificationsPage(model: model)
            case .privacy: PrivacyPage(model: model)
            case .dataStorage: DataStoragePage(model: model)
            case .sessions: SessionsPage(model: model)
            case .appearance: AppearancePage()
            case .folders: FoldersPage(model: model)
            case .folderEditor(let id): FolderEditorPage(model: model, folderID: id)
            case .sidebar: SidebarPage(model: model)
            case .nodogramFeatures: FeaturesPage(model: model)
            case .about: AboutPage(model: model)
            case .language: LanguagePage()
            case .filters: AboutPage(model: model)
            }
        }
        .id(model.settingsPage)
        .navigationTitle(model.settingsPage.title)
    }
}

/// A centred grouped form, the shape every settings page shares.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
    }
}

/// A page header with a big icon and one explanatory line, as Telegram puts
/// at the top of Chat Folders.
struct SettingsHero: View {
    let symbol: String
    let tint: (Double, Double, Double)
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color(red: tint.0, green: tint.1, blue: tint.2).gradient, in: RoundedRectangle(cornerRadius: 16))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Footnote text under a section.
struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
