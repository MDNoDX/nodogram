//  Settings, middle column: the profile card and Telegram-style grouped rows
//  with coloured icon tiles. The chosen page opens on the right.

import SwiftUI
import NodogramDomain
import NodogramUI

struct SettingsListView: View {
    let model: AppModel

    @State private var profile: ProfileInfo?
    @State private var query = ""

    var body: some View {
        List(selection: Binding(get: { model.settingsPage.listKey }, set: { key in
            if let page = SettingsPage.fromListKey(key) { model.settingsPage = page }
        })) {
            Section {
                profileCard
                    .tag(SettingsPage.profile.listKey)
            }
            ForEach(Array(SettingsPage.groups.dropFirst().enumerated()), id: \.offset) { _, group in
                let rows = group.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows, id: \.listKey) { page in
                            SettingsRowLabel(page: page, value: value(for: page))
                                .tag(page.listKey)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .searchable(text: $query, placement: .toolbar, prompt: "Search settings")
        .task { profile = await model.loadProfile() }
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            let chat = model.myUserID.flatMap { model.chatsByID[ChatID($0.rawValue)] }
            Avatar(title: profile?.displayName ?? "Me", seed: profile?.userID.rawValue ?? 0, size: 52,
                   imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile?.displayName ?? "Loading…").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    if profile?.isPremium == true {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.purple)
                    }
                }
                if let profile {
                    Text(Self.formatPhone(profile.phoneNumber)).font(.system(size: 12)).foregroundStyle(.secondary)
                    if !profile.username.isEmpty {
                        Text("@\(profile.username)").font(.system(size: 12)).foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func value(for page: SettingsPage) -> String? {
        switch page {
        case .folders: return model.folders.isEmpty ? nil : "\(model.folders.count)"
        case .nodogramFeatures:
            let count = model.unseenDeletedCount + model.unseenTypingCount
            return count > 0 ? "\(count) new" : nil
        default: return nil
        }
    }

    static func formatPhone(_ digits: String) -> String {
        guard !digits.isEmpty else { return "" }
        return digits.hasPrefix("+") ? digits : "+" + digits
    }
}

struct SettingsRowLabel: View {
    let page: SettingsPage
    var value: String?

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: page.symbol, tint: page.tint)
            Text(page.title).font(.system(size: 13))
            Spacer(minLength: 4)
            if let value {
                Text(value).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SettingsIcon: View {
    let symbol: String
    let tint: (Double, Double, Double)

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color(red: tint.0, green: tint.1, blue: tint.2), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension SettingsPage {
    /// A plain key for List selection (the editor page shares "folders").
    var listKey: String {
        switch self {
        case .profile: return "profile"
        case .general: return "general"
        case .notifications: return "notifications"
        case .privacy: return "privacy"
        case .dataStorage: return "dataStorage"
        case .sessions: return "sessions"
        case .appearance: return "appearance"
        case .folders, .folderEditor: return "folders"
        case .sidebar: return "sidebar"
        case .nodogramFeatures: return "nodogramFeatures"
        case .about: return "about"
        }
    }

    static func fromListKey(_ key: String?) -> SettingsPage? {
        let all: [SettingsPage] = [.profile, .general, .notifications, .privacy, .dataStorage, .sessions,
                                   .appearance, .folders, .sidebar, .nodogramFeatures, .about]
        return all.first { $0.listKey == key }
    }
}
