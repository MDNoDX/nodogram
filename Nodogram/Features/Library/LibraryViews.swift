//  The non-chat sidebar sections: Media, Files, Links, Voice Messages,
//  Starred, Recently Viewed and Local Archive. Each fills the middle column;
//  choosing an item opens its chat at that message.

import AppKit
import SwiftUI
import NodogramDomain
import NodogramPlatform
import NodogramTelegram
import NodogramUI

struct LibrarySectionView: View {
    let model: AppModel

    var body: some View {
        switch model.selectedDestination {
        case .media: ContentBrowser(model: model, kind: .media)
        case .files: ContentBrowser(model: model, kind: .files)
        case .links: ContentBrowser(model: model, kind: .links)
        case .voiceMessages: ContentBrowser(model: model, kind: .voice)
        case .starred: StarredList(model: model)
        case .recentlyViewed: RecentChatsList(model: model)
        case .localArchive: LocalArchiveList(model: model)
        case .typingLog: TypingLogView(model: model)
        case .storyViews: StoryViewsView(model: model)
        case .myActivity: MyActivityView(model: model)
        default:
            EmptyStateView(icon: model.selectedDestination.icon, title: model.selectedDestination.title,
                           message: "Choose a section in the sidebar.")
        }
    }
}

// MARK: - Shared content

enum ContentKind: String {
    case media, files, links, voice

    var filter: TelegramGateway.MediaFilter {
        switch self {
        case .media: return .photosAndVideos
        case .files: return .files
        case .links: return .links
        case .voice: return .voice
        }
    }

    var emptyTitle: String {
        switch self {
        case .media: return "No photos or videos"
        case .files: return "No files"
        case .links: return "No links"
        case .voice: return "No voice messages"
        }
    }

    var icon: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .files: return "doc"
        case .links: return "link"
        case .voice: return "waveform"
        }
    }
}

struct ContentBrowser: View {
    let model: AppModel
    let kind: ContentKind

    enum Scope: Hashable { case everywhere, chat(ChatID) }

    @State private var scope: Scope
    /// Shown inside a chat's info panel: no scope picker, that chat only.
    private let isEmbedded: Bool

    init(model: AppModel, kind: ContentKind, chat: ChatID? = nil) {
        self.model = model
        self.kind = kind
        self._scope = State(initialValue: chat.map { .chat($0) } ?? .everywhere)
        self.isEmbedded = chat != nil
    }
    @State private var items: [Message] = []
    @State private var isLoading = false
    @State private var query = ""

    private var filtered: [Message] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { message in
            message.text.lowercased().contains(q)
                || model.chatTitle(message.chatID).lowercased().contains(q)
                || (message.media?.suggestedFileName.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isEmbedded {
                header
                Divider()
            }
            Group {
                if isLoading, items.isEmpty {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    EmptyStateView(icon: kind.icon, title: kind.emptyTitle,
                                   message: scope == .everywhere
                                       ? "Nothing like this in your recent chats yet."
                                       : "Nothing like this in this chat yet.")
                } else {
                    content
                }
            }
        }
        .task(id: "\(kind.rawValue)-\(scope)") { await load() }
        .onChange(of: model.selectedChatID) { _, chat in
            if case .chat = scope, let chat { scope = .chat(chat) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Scope", selection: $scope) {
                Text("All Chats").tag(Scope.everywhere)
                if let chat = model.selectedChat {
                    Text(chat.title).lineLimit(1).tag(Scope.chat(chat.id))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            Spacer(minLength: 4)
            TextField("Filter", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 130)
            Button {
                Task { await load() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh")
                .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .media:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: 2)], spacing: 2) {
                    ForEach(filtered, id: \.uniqueKey) { message in
                        MediaTile(message: message, model: model)
                    }
                }
                .padding(2)
            }
        case .files:
            List(filtered, id: \.uniqueKey) { FileRow(message: $0, model: model) }
                .listStyle(.inset)
        case .links:
            List(filtered, id: \.uniqueKey) { LinkRow(message: $0, model: model) }
                .listStyle(.inset)
        case .voice:
            List(filtered, id: \.uniqueKey) { VoiceRow(message: $0, model: model) }
                .listStyle(.inset)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        switch scope {
        case .everywhere:
            items = await model.loadContent(kind.filter)
        case .chat(let chatID):
            items = await model.loadContent(kind.filter, in: chatID)
        }
    }
}

extension Message {
    var uniqueKey: String { "\(chatID.rawValue)-\(id.rawValue)" }
}

private struct ContextLine: View {
    let message: Message
    let model: AppModel

    var body: some View {
        Text("\(model.chatTitle(message.chatID)) · \(RelativeTimeFormatter.short(message.date))")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: - Media grid

private struct MediaTile: View {
    let message: Message
    let model: AppModel

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { image }
            .overlay(alignment: .bottomLeading) {
                if case .video(let video) = message.media {
                    Text(formatDuration(Double(video.duration)))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(5)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { model.jump(to: message.id, in: message.chatID) }
            .help("\(model.chatTitle(message.chatID)) · \(RelativeTimeFormatter.exact(message.date))")
            .contextMenu {
                Button("Show in Chat") { model.jump(to: message.id, in: message.chatID) }
                MediaActions.menu(for: message, model: model)
            }
    }

    @ViewBuilder
    private var image: some View {
        switch message.media {
        case .photo(let photo):
            let state = model.files.state(for: photo.preview)
            ZStack {
                MinithumbnailView(data: photo.minithumbnail)
                LocalImageView(path: state.file.localPath, maxPixel: 400) { Color.clear }
            }
            .task(id: photo.preview.id) { _ = await model.fetch(photo.preview, priority: 2) }
        case .video(let video):
            let thumb = video.thumbnail.map { model.files.state(for: $0) }
            ZStack {
                MinithumbnailView(data: video.minithumbnail)
                LocalImageView(path: thumb?.file.localPath, maxPixel: 400) { Color.clear }
            }
            .task(id: video.file.id) {
                if let thumbnail = video.thumbnail { _ = await model.fetch(thumbnail, priority: 2) }
            }
        default:
            Color.secondary.opacity(0.1)
        }
    }
}

// MARK: - Files

private struct FileRow: View {
    let message: Message
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.14))
                Text(fileExtension.uppercased().prefix(4))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    if !size.isEmpty { Text(size).font(.system(size: 11)).foregroundStyle(.secondary) }
                    ContextLine(message: message, model: model)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .onTapGesture { model.jump(to: message.id, in: message.chatID) }
        .contextMenu {
            Button("Show in Chat") { model.jump(to: message.id, in: message.chatID) }
            Button("Open") { open() }.disabled(!message.canBeSaved)
            MediaActions.menu(for: message, model: model)
        }
    }

    private var document: DocumentMedia? {
        if case .document(let doc) = message.media { return doc }
        return nil
    }
    private var name: String { document?.fileName.isEmpty == false ? document!.fileName : "File" }
    private var fileExtension: String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "file" : ext
    }
    private var size: String { document?.file.sizeDescription ?? "" }

    private func open() {
        guard let document else { return }
        MediaActions.openDocument(message, file: document.file, model: model)
    }
}

// MARK: - Links

private struct LinkRow: View {
    let message: Message
    let model: AppModel

    var body: some View {
        let url = Self.firstURL(in: message)
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.14))
                Text(url?.host()?.replacingOccurrences(of: "www.", with: "").prefix(1).uppercased() ?? "#")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "Link")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let url {
                    Text(url.absoluteString)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1).truncationMode(.middle)
                }
                if !message.text.isEmpty {
                    Text(message.text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                }
                ContextLine(message: message, model: model)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.jump(to: message.id, in: message.chatID) }
        .contextMenu {
            if let url {
                Button("Open Link") { LinkPolicy.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
            Button("Show in Chat") { model.jump(to: message.id, in: message.chatID) }
        }
    }

    /// Entity offsets are UTF-16, as Telegram sends them.
    static func firstURL(in message: Message) -> URL? {
        let utf16 = Array(message.text.utf16)
        for entity in message.entities {
            switch entity.kind {
            case .textLink(let link):
                if let url = URL(string: link) { return url }
            case .url:
                guard entity.offset >= 0, entity.offset + entity.length <= utf16.count else { continue }
                let raw = String(decoding: utf16[entity.offset..<entity.offset + entity.length], as: UTF16.self)
                let withScheme = raw.contains("://") ? raw : "https://\(raw)"
                if let url = URL(string: withScheme) { return url }
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - Voice

private struct VoiceRow: View {
    let message: Message
    let model: AppModel

    var body: some View {
        let playback = AudioPlayback.shared
        let isCurrent = playback.currentID == message.id
        HStack(spacing: 10) {
            Button {
                guard case .voiceNote(let voice) = message.media else { return }
                playback.toggle(message, file: voice.file) { await model.fetch($0, priority: 32) }
            } label: {
                Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.isOutgoing ? "You" : (message.senderName.isEmpty ? model.chatTitle(message.chatID) : message.senderName))
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                HStack(spacing: 4) {
                    if case .voiceNote(let voice) = message.media {
                        Text(formatDuration(Double(voice.duration)))
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ContextLine(message: message, model: model)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Chat") { model.jump(to: message.id, in: message.chatID) }
            MediaActions.menu(for: message, model: model)
        }
    }
}

// MARK: - Starred

private struct StarredList: View {
    let model: AppModel

    var body: some View {
        if model.starred.isEmpty {
            EmptyStateView(icon: "star", title: "No starred messages",
                           message: "Right-click any message and choose Star to keep it here. Stars stay on this Mac.")
        } else {
            List(model.starred) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.chatTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(RelativeTimeFormatter.short(item.date)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Group {
                        if let label = item.attachmentLabel {
                            Text(label).foregroundStyle(Theme.accent)
                                + Text(item.text.isEmpty ? "" : " · \(item.text)").foregroundStyle(.secondary)
                        } else {
                            Text(item.text).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 12))
                    .lineLimit(3)
                    if !item.senderName.isEmpty {
                        Text(item.senderName).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { model.jump(to: MessageID(item.messageID), in: ChatID(item.chatID)) }
                .contextMenu {
                    Button("Show in Chat") { model.jump(to: MessageID(item.messageID), in: ChatID(item.chatID)) }
                    Button("Unstar", role: .destructive) { model.unstar(item) }
                }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Recently viewed

private struct RecentChatsList: View {
    let model: AppModel

    var body: some View {
        let chats = model.recentChatIDs.compactMap { model.chatsByID[$0] }
        if chats.isEmpty {
            EmptyStateView(icon: "clock", title: "Nothing viewed yet",
                           message: "Chats you open appear here, most recent first.")
        } else {
            List(selection: Binding(get: { model.selectedChatID }, set: { model.select($0) })) {
                ForEach(chats) { chat in
                    ChatRow(chat: chat, activity: model.activityText(for: chat.id))
                        .tag(chat.id)
                        .onAppear { model.ensureAvatar(for: chat.id) }
                }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom) {
                Button("Clear History") { model.clearRecentlyViewed() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .padding(8)
            }
        }
    }
}

// MARK: - Deleted messages

private struct LocalArchiveList: View {
    let model: AppModel

    @State private var items: [Message] = []
    @State private var loaded = false
    @State private var query = ""

    private var filtered: [Message] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.senderName.localizedCaseInsensitiveContains(query)
                || model.chatTitle($0.chatID).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if !model.keepsDeletedMessages {
                VStack(spacing: 14) {
                    EmptyStateView(
                        icon: "trash.circle", title: "Keeping deleted messages is off",
                        message: "Turn it on to keep a private, encrypted copy of messages others delete. Self-destructing and protected messages are never kept.")
                    Button("Turn On") {
                        UserDefaults.standard.set(true, forKey: AppModel.keepDeletedKey)
                        model.settingsPage = .nodogramFeatures
                        model.selectedDestination = .settings
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 40)
            } else if loaded, items.isEmpty {
                EmptyStateView(icon: "trash.slash", title: "Nothing deleted yet",
                               message: "When someone deletes a message this Mac received, it stays in the chat marked “Deleted” and appears here.")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(items.count) deleted messages").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        TextField("Search", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 150)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    List(filtered, id: \.uniqueKey) { message in
                        DeletedRow(model: model, message: message)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .task {
            model.markDeletedSeen()
            items = await model.locallyArchivedMessages()
            loaded = true
        }
        .onChange(of: model.unseenDeletedCount) { _, count in
            guard count > 0 else { return }
            model.markDeletedSeen()
            Task { items = await model.locallyArchivedMessages() }
        }
    }
}

private struct DeletedRow: View {
    let model: AppModel
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            let chat = model.chatsByID[message.chatID]
            Avatar(title: message.senderName.isEmpty ? model.chatTitle(message.chatID) : message.senderName,
                   seed: message.senderID?.rawValue ?? message.chatID.rawValue, size: 34,
                   imagePath: message.senderID == nil ? chat?.avatarPath : nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(message.isOutgoing ? "You" : (message.senderName.isEmpty ? model.chatTitle(message.chatID) : message.senderName))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if !message.senderName.isEmpty, model.chatTitle(message.chatID) != message.senderName {
                        Text("in \(model.chatTitle(message.chatID))").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                Group {
                    if let label = message.attachmentLabel {
                        Text(label + (message.text.isEmpty ? "" : " · ")).foregroundStyle(Theme.accent)
                            + Text(message.text)
                    } else {
                        Text(message.text)
                    }
                }
                .font(.system(size: 12.5))
                .lineLimit(6)
                .textSelection(.enabled)
                HStack(spacing: 8) {
                    Label("sent \(RelativeTimeFormatter.short(message.date))", systemImage: "paperplane")
                    if let deletedAt = message.deletedAt {
                        Label("deleted \(RelativeTimeFormatter.short(deletedAt))", systemImage: "trash")
                            .foregroundStyle(Theme.failure)
                            .help(RelativeTimeFormatter.exact(deletedAt))
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedDestination = .allChats
            model.jump(to: message.id, in: message.chatID)
        }
        .contextMenu {
            Button("Show in Chat") {
                model.selectedDestination = .allChats
                model.jump(to: message.id, in: message.chatID)
            }
            Button("Copy Text") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.text, forType: .string)
            }
        }
    }
}
