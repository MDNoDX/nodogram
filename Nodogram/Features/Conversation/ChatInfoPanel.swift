//  The ⋯ menu in a chat's header, and the profile panel on the right: who
//  this is, what Telegram shares about them, the groups you share and what
//  they wrote there, their former names, and what Nodogram kept.

import AppKit
import SwiftUI
import NodogramDomain
import NodogramUI

// MARK: - ⋯ menu

struct ChatActionsMenu: View {
    let model: AppModel
    let chat: Chat
    @Binding var editingContact: Bool
    @Binding var confirm: ChatConfirmation?

    private var userID: UserID? {
        if case .privateChat(let user) = chat.kind { return user }
        return nil
    }

    var body: some View {
        if userID != nil, !chat.isSavedMessages {
            Button { editingContact = true } label: { Label("Edit Contact…", systemImage: "square.and.pencil") }
        }
        Button { model.infoPanelVisible = true } label: { Label("Info", systemImage: "info.circle") }
        Button { model.beginConversationSearch() } label: { Label("Search", systemImage: "magnifyingglass") }
        Menu {
            Button("For 1 Hour") { model.mute(chat.id, for: 3600) }
            Button("For 8 Hours") { model.mute(chat.id, for: 8 * 3600) }
            Button("For 2 Days") { model.mute(chat.id, for: 2 * 86_400) }
            Button("Forever") { model.mute(chat.id, for: 366 * 86_400) }
            if chat.isMuted { Divider(); Button("Unmute") { model.mute(chat.id, for: 0) } }
        } label: { Label(chat.isMuted ? "Muted" : "Mute", systemImage: chat.isMuted ? "bell.slash.fill" : "bell.slash") }
        if let user = userID, !chat.isSavedMessages, !chat.isBot {
            Button { model.createGroup(title: "\(chat.title) & me", with: [user]) } label: {
                Label("Create Group", systemImage: "person.2.badge.plus")
            }
        }
        Menu {
            Button("Default") { model.setWallpaper(nil, for: chat.id) }
            Divider()
            ForEach(Theme.wallpapers.indices, id: \.self) { index in
                Button(Theme.wallpapers[index].name) { model.setWallpaper(index, for: chat.id) }
            }
        } label: { Label("Change Wallpaper", systemImage: "paintbrush") }
        Button { model.assistantChatRequested = true } label: { Label("Understand this Chat (AI)", systemImage: "sparkles") }
        Button { model.setTranslating(chat.id, !model.isTranslating(chat.id)) } label: {
            Label(model.isTranslating(chat.id) ? "Stop Translating" : "Translate Chat", systemImage: "translate")
        }
        Button { model.summaryRequested = true } label: { Label("Summarize with Apple Intelligence…", systemImage: "sparkles") }
            .disabled(!model.canSummarize)
        Button { model.exportChat(chat.id) } label: { Label("Export Chat History…", systemImage: "square.and.arrow.up") }
        Divider()
        Menu {
            Button("Off") { model.setAutoDelete(chat.id, seconds: 0) }
            Button("After 1 Day") { model.setAutoDelete(chat.id, seconds: 86_400) }
            Button("After 1 Week") { model.setAutoDelete(chat.id, seconds: 7 * 86_400) }
            Button("After 1 Month") { model.setAutoDelete(chat.id, seconds: 31 * 86_400) }
        } label: { Label("Auto-Delete Messages", systemImage: "timer") }
        Button { confirm = .clear } label: { Label("Clear Chat History…", systemImage: "xmark.circle") }
        if let user = userID, !chat.isSavedMessages {
            Button { confirm = .block(user) } label: { Label("Block User…", systemImage: "hand.raised") }
        }
        Button(role: .destructive) { confirm = .delete } label: {
            Label(userID == nil ? "Leave Chat…" : "Delete Chat…", systemImage: "trash")
        }
    }
}

enum ChatConfirmation: Identifiable {
    case clear, delete, block(UserID)
    var id: String {
        switch self {
        case .clear: return "clear"
        case .delete: return "delete"
        case .block(let u): return "block-\(u.rawValue)"
        }
    }
}

// MARK: - Panel

struct ChatInfoPanel: View {
    let model: AppModel
    let chat: Chat

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isPerson ? "User Info" : (chat.kind == .channel ? "Channel Info" : "Group Info"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { model.infoPanelVisible = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Close")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                if case .privateChat(let user) = chat.kind {
                    PersonInfo(model: model, chat: chat, user: user).id(user)
                } else {
                    GroupInfo(model: model, chat: chat).id(chat.id)
                }
            }
        }
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var isPerson: Bool {
        if case .privateChat = chat.kind { return true }
        return false
    }
}

private struct PersonInfo: View {
    let model: AppModel
    let chat: Chat
    let user: UserID

    @State private var activity = PersonActivity()
    @State private var mediaKind: ContentKind = .media

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let p = activity.profile { details(p) }
            observations
            if !activity.identities.isEmpty { nameHistory }
            commonGroups
            if !activity.groupMessages.isEmpty { theirMessages }
            sharedMedia
        }
        .padding(14)
        .task {
            await model.loadActivity(for: user) { activity = $0 }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Avatar(title: chat.title, seed: chat.id.rawValue, size: 88, imagePath: chat.avatarPath,
                   thumbnail: chat.avatarThumbnail, isOnline: chat.presence == .online)
            HStack(spacing: 4) {
                Text(chat.title).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
                if activity.profile?.isVerified == true { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
                if activity.profile?.isPremium == true { Image(systemName: "star.fill").foregroundStyle(.purple).font(.system(size: 11)) }
            }
            Text(PresenceFormatter.describe(chat.presence, now: Date()) ?? (chat.isBot ? "bot" : ""))
                .font(.system(size: 12)).foregroundStyle(chat.presence == .online ? Theme.accent : .secondary)
            if activity.profile?.usesUnofficialApp == true {
                Label("Uses an unofficial Telegram app", systemImage: "exclamationmark.shield")
                    .font(.system(size: 11)).foregroundStyle(Theme.warning)
            }
            HStack(spacing: 8) {
                PanelButton(title: "Message", symbol: "bubble.left.fill") { model.infoPanelVisible = false }
                PanelButton(title: chat.isMuted ? "Unmute" : "Mute", symbol: chat.isMuted ? "bell.fill" : "bell.slash.fill") {
                    model.mute(chat.id, for: chat.isMuted ? 0 : 366 * 86_400)
                }
                PanelButton(title: "Export", symbol: "square.and.arrow.up") { model.exportChat(chat.id) }
                if let p = activity.profile, !chat.isSavedMessages {
                    PanelButton(title: p.isBlocked ? "Unblock" : "Block", symbol: "hand.raised.fill") {
                        model.setBlocked(user, !p.isBlocked)
                        Task { activity.profile = await model.gatewayProfile(user) }
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func details(_ p: PersonProfile) -> some View {
        Card {
            if !p.phoneNumber.isEmpty {
                InfoRow(label: "mobile", value: SettingsListView.formatPhone(p.phoneNumber), copy: "+" + p.phoneNumber)
            }
            ForEach(p.usernames, id: \.self) { name in
                InfoRow(label: "username", value: "@\(name)", copy: "https://t.me/\(name)", accent: true)
            }
            ForEach(p.collectibleUsernames.filter { !p.usernames.contains($0) }, id: \.self) { name in
                InfoRow(label: "collectible username", value: "@\(name)", copy: "@\(name)")
            }
            ForEach(p.disabledUsernames, id: \.self) { name in
                InfoRow(label: "inactive username", value: "@\(name)", copy: "@\(name)")
            }
            if !p.bio.isEmpty { InfoRow(label: "bio", value: p.bio, copy: p.bio) }
            if let birthday = p.birthday { InfoRow(label: "birthday", value: birthday, copy: birthday) }
            if !p.note.isEmpty { InfoRow(label: "your note", value: p.note, copy: p.note) }
            InfoRow(label: "user ID", value: String(p.userID.rawValue), copy: String(p.userID.rawValue))
            InfoRow(label: "contact",
                    value: p.isMutualContact ? "In your contacts — they saved you too"
                         : p.isContact ? "In your contacts (they haven't saved you, or hide it)"
                         : "Not in your contacts",
                    copy: nil)
        }
    }

    private var observations: some View {
        Card(title: "Kept by Nodogram") {
            StatRow(symbol: "trash", text: "\(activity.deletedCount) deleted messages kept") {
                model.selectedDestination = .localArchive
            }
            StatRow(symbol: "ellipsis.bubble",
                    text: "Typed to you \(activity.typingCount) times · \(activity.abandonedTypingCount) without sending") {
                model.selectedDestination = .typingLog
            }
            StatRow(symbol: "eye", text: "Viewed your stories \(activity.storyViews) times") {
                model.selectedDestination = .storyViews
            }
        }
    }

    private var nameHistory: some View {
        Card(title: "Names and usernames seen") {
            ForEach(Array(activity.identities.reversed().enumerated()), id: \.offset) { index, identity in
                VStack(alignment: .leading, spacing: 1) {
                    Text(identity.name.isEmpty ? "—" : identity.name).font(.system(size: 12.5, weight: index == 0 ? .semibold : .regular))
                    if !identity.usernames.isEmpty {
                        Text(identity.usernames.map { "@\($0)" }.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                    }
                    Text(index == 0 ? "current · since \(identity.seenAt.formatted(date: .abbreviated, time: .omitted))"
                                    : "seen \(identity.seenAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Recorded on this Mac from the moment Nodogram first saw them.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
        }
    }

    private var commonGroups: some View {
        Card(title: activity.isLoading && activity.commonGroups.isEmpty ? "Groups in common…" : "\(activity.commonGroups.count) groups in common") {
            if activity.commonGroups.isEmpty, !activity.isLoading {
                Text("None you can see. Telegram only shows groups you are both in.").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(activity.commonGroups, id: \.self) { id in
                Button {
                    model.infoPanelVisible = false
                    model.select(id)
                } label: {
                    HStack(spacing: 8) {
                        let group = model.chatsByID[id]
                        Avatar(title: group?.title ?? model.chatTitle(id), seed: id.rawValue, size: 26,
                               imagePath: group?.avatarPath, thumbnail: group?.avatarThumbnail)
                        Text(group?.title ?? model.chatTitle(id)).font(.system(size: 12.5)).lineLimit(1)
                        Spacer()
                        if let count = activity.groupMessageCounts[id], count > 0 {
                            Text("\(count) msgs").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var theirMessages: some View {
        Card(title: "Their messages in shared groups") {
            ForEach(activity.groupMessages.prefix(40), id: \.uniqueKey) { message in
                Button {
                    model.infoPanelVisible = false
                    model.jump(to: message.id, in: message.chatID)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.text.isEmpty ? (message.attachmentLabel ?? "Message") : message.text)
                            .font(.system(size: 12)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(model.chatTitle(message.chatID)) · \(RelativeTimeFormatter.short(message.date))")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sharedMedia: some View {
        Card(title: "Shared in this chat") {
            Picker("", selection: $mediaKind) {
                Text("Media").tag(ContentKind.media)
                Text("Files").tag(ContentKind.files)
                Text("Links").tag(ContentKind.links)
                Text("Voice").tag(ContentKind.voice)
            }
            .pickerStyle(.segmented).labelsHidden()
            ContentBrowser(model: model, kind: mediaKind, chat: chat.id)
                .id(mediaKind)
                .frame(height: 320)
        }
    }
}

private struct GroupInfo: View {
    let model: AppModel
    let chat: Chat

    @State private var about = ""
    @State private var managing: GroupSummary?
    @State private var mediaKind: ContentKind = .media

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 6) {
                Avatar(title: chat.title, seed: chat.id.rawValue, size: 88, imagePath: chat.avatarPath, thumbnail: chat.avatarThumbnail)
                Text(chat.title).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.center)
                if chat.memberCount > 0 {
                    Text("\(chat.memberCount.formatted()) \(chat.kind == .channel ? "subscribers" : "members")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            if !about.isEmpty {
                Card { InfoRow(label: "description", value: about, copy: about) }
            }
            Card {
                InfoRow(label: "chat ID", value: String(chat.id.rawValue), copy: String(chat.id.rawValue))
                if let summary = model.myGroups().first(where: { $0.id == chat.id }) {
                    Button("My messages, members and leaving…") { managing = summary }
                        .buttonStyle(.link)
                }
            }
            Card(title: "Shared in this chat") {
                Picker("", selection: $mediaKind) {
                    Text("Media").tag(ContentKind.media)
                    Text("Files").tag(ContentKind.files)
                    Text("Links").tag(ContentKind.links)
                    Text("Voice").tag(ContentKind.voice)
                }
                .pickerStyle(.segmented).labelsHidden()
                ContentBrowser(model: model, kind: mediaKind, chat: chat.id).id(mediaKind).frame(height: 320)
            }
        }
        .padding(14)
        .task { about = await model.chatDescription(chat.id) }
        .sheet(item: $managing) { group in GroupManageSheet(model: model, group: group) {} }
    }
}

// MARK: - Building blocks

private struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    let copy: String?
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13)).foregroundStyle(accent ? Theme.accent : .primary).textSelection(.enabled)
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if let copy {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copy, forType: .string)
                }
            }
        }
    }
}

private struct StatRow: View {
    let symbol: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 18)
                Text(text).font(.system(size: 12.5))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PanelButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(.system(size: 10.5))
            }
            .foregroundStyle(Theme.accent)
            .frame(width: 64, height: 46)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Saves or renames a contact.
struct EditContactSheet: View {
    let model: AppModel
    let user: UserID
    @State var firstName: String
    @State var lastName: String
    let phone: String
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Contact").font(.headline)
            TextField("First name", text: $firstName).textFieldStyle(.roundedBorder)
            TextField("Last name", text: $lastName).textFieldStyle(.roundedBorder)
            if !phone.isEmpty { Text("+\(phone)").foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(Theme.failure).font(.system(size: 12)) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        error = await model.saveContact(user, firstName: firstName, lastName: lastName, phone: phone)
                        if error == nil { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
