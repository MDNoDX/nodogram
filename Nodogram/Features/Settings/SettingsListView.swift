//  Settings, middle column, laid out like Telegram's: search, the profile
//  card, then grouped rows with coloured icon tiles and chevrons. The chosen
//  row is filled with the accent; its page opens on the right.

import SwiftUI
import NodogramDomain
import NodogramUI

struct SettingsListView: View {
    let model: AppModel

    @State private var profile: ProfileInfo?
    @State private var query = ""
    @State private var sessionCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $query, prompt: "Search")
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 14) {
                    if query.isEmpty {
                        profileCard
                        VStack(spacing: 2) {
                            let _ = model.accountsVersion
                            ForEach(model.accountIDs, id: \.self) { id in
                                if id != model.activeAccountID {
                                    actionRow("Switch to \(Accounts.name(id))", symbol: "person.crop.circle") {
                                        model.switchAccount(to: id)
                                    }
                                }
                            }
                            actionRow("Add Account", symbol: "person.badge.plus") { model.addAccount() }
                            actionRow("Ask a Question", symbol: "questionmark.bubble") { model.openSupportChat() }
                            actionRow("Telegram FAQ", symbol: "book") {
                                if let url = URL(string: "https://telegram.org/faq") { NSWorkspace.shared.open(url) }
                            }
                        }
                        .padding(6)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    }
                    ForEach(Array(SettingsPage.groups.dropFirst().enumerated()), id: \.offset) { _, group in
                        let rows = group.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                        if !rows.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(rows, id: \.listKey) { page in row(page) }
                            }
                            .padding(6)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    Text("Nodogram \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · TDLib \(model.tdlibVersion ?? "")")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Settings")
        .task {
            profile = await model.loadProfile()
            sessionCount = await model.loadSessions().count
        }
    }

    private var profileCard: some View {
        Button { model.settingsPage = .profile } label: {
            HStack(spacing: 12) {
                let chat = model.myUserID.flatMap { model.chatsByID[ChatID($0.rawValue)] }
                Avatar(title: profile?.displayName ?? "Me", seed: profile?.userID.rawValue ?? 0, size: 54,
                       imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(profile?.displayName ?? "Loading…").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if profile?.isPremium == true {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.purple)
                        }
                    }
                    if let profile {
                        Text(Self.formatPhone(profile.phoneNumber)).font(.system(size: 12))
                            .foregroundStyle(isSelected(.profile) ? .white.opacity(0.85) : .secondary)
                        if !profile.username.isEmpty {
                            Text("@\(profile.username)").font(.system(size: 12))
                                .foregroundStyle(isSelected(.profile) ? .white : Theme.accent)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(isSelected(.profile) ? .white : .primary)
            .padding(10)
            .background(isSelected(.profile) ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary.opacity(0.35)),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ page: SettingsPage) -> Bool { model.settingsPage.listKey == page.listKey }

    private func row(_ page: SettingsPage) -> some View {
        let selected = isSelected(page)
        return Button { model.settingsPage = page } label: {
            HStack(spacing: 10) {
                SettingsIcon(symbol: page.symbol, tint: page.tint)
                Text(page.title).font(.system(size: 13))
                Spacer(minLength: 4)
                if let value = value(for: page) {
                    Text(value).font(.system(size: 12))
                        .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? .white.opacity(0.8) : Color.secondary.opacity(0.6))
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(selected ? Theme.accent : .clear, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.accent).frame(width: 24)
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.accent)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func value(for page: SettingsPage) -> String? {
        switch page {
        case .folders: return model.folders.isEmpty ? nil : "\(model.folders.count)"
        case .sessions: return sessionCount.map { "\($0)" }
        case .language: return "English"
        case .nodogramFeatures:
            let count = model.unseenDeletedCount + model.unseenTypingCount
            return count > 0 ? "\(count) new" : nil
        default: return nil
        }
    }

    /// "+998 94 137 23 37" — grouped the way Telegram shows numbers.
    static func formatPhone(_ digits: String) -> String {
        let raw = digits.filter(\.isNumber)
        guard !raw.isEmpty else { return "" }
        if raw.hasPrefix("998"), raw.count == 12 {
            let d = Array(raw)
            return "+998 \(String(d[3...4])) \(String(d[5...7])) \(String(d[8...9])) \(String(d[10...11]))"
        }
        if raw.hasPrefix("7"), raw.count == 11 {
            let d = Array(raw)
            return "+7 \(String(d[1...3])) \(String(d[4...6])) \(String(d[7...8])) \(String(d[9...10]))"
        }
        return "+" + raw
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
            .background(Color(red: tint.0, green: tint.1, blue: tint.2).gradient, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// A search box that filters as you type and focuses on click anywhere in it.
struct SearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Clear")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

extension SettingsPage {
    /// A plain key for selection (the editor page belongs to "folders").
    var listKey: String {
        switch self {
        case .profile: return "profile"
        case .general: return "general"
        case .notifications: return "notifications"
        case .privacy: return "privacy"
        case .dataStorage: return "dataStorage"
        case .sessions: return "sessions"
        case .appearance: return "appearance"
        case .language: return "language"
        case .assistant: return "assistant"
        case .folders, .folderEditor: return "folders"
        case .sidebar: return "sidebar"
        case .nodogramFeatures: return "nodogramFeatures"
        case .filters: return "filters"
        case .about: return "about"
        }
    }
}
