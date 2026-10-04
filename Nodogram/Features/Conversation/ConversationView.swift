//  Conversation pane.

import SwiftUI
import NodogramCore
import NodogramDomain
import NodogramUI
import NodogramPlatform
import NodogramTelegram

public struct ConversationView: View {
    private let model: AppModel

    /// Bumped every 30 s so "last seen 3 minutes ago" stays true.
    @State private var clock = Date()

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        if let chat = model.selectedChat {
            VStack(spacing: 0) {
                ConversationHeader(
                    chat: chat,
                    subtitle: subtitle(for: chat, now: clock),
                    isActivity: model.activityText(for: chat.id) != nil
                )
                Divider()

                if let search = model.conversationSearch {
                    ConversationSearchBar(model: model, state: search)
                    Divider()
                }

                HStack(spacing: 0) {
                    MessageTimeline(model: model, chat: chat)
                        .id(chat.id)   // fresh scroll state per chat
                        .frame(maxWidth: .infinity)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard chat.canPost else { return false }
                            attach(urls)
                            return true
                        }

                    if let comments = model.comments {
                        Divider()
                        CommentsPanel(model: model, state: comments)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: model.comments?.postMessageID)

                if let error = model.conversationError {
                    ErrorBanner(message: error, onDismiss: model.dismissConversationError)
                }

                bottomBar(for: chat)
            }
            .background(ScreenshotProtection(isProtected: chat.hasProtectedContent))
            .sheet(item: Binding(get: { model.forwardRequest }, set: { model.forwardRequest = $0 })) { request in
                ForwardSheet(model: model, request: request)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    clock = Date()
                }
            }
        } else {
            EmptyStateView(
                icon: "bubble.left.and.text.bubble.right",
                title: L10n.noConversationTitle,
                message: L10n.noConversationBody
            )
            .navigationTitle("Nodogram")
        }
    }

    /// The composer, or what replaces it: the selection bar while selecting,
    /// and a Mute button in channels the user only reads — as in Telegram.
    @ViewBuilder
    private func bottomBar(for chat: Chat) -> some View {
        if model.isSelecting {
            SelectionBar(model: model)
        } else if !chat.canPost {
            ReadOnlyBar(model: model, chat: chat)
        } else {
            ComposerView(
                chatID: chat.id,
                text: Binding(
                    get: { model.draftText },
                    set: {
                        model.draftText = $0
                        model.draftTextChanged()
                    }
                ),
                draftIndicatorVisible: model.draftIndicatorVisible,
                mode: model.composerMode,
                onCancelMode: model.cancelComposerMode,
                onAttach: attach,
                onSend: model.submitComposer
            )
        }
    }

    private func attach(_ urls: [URL]) {
        Task {
            var files: [OutgoingFile] = []
            for url in urls { files.append(await OutgoingFiles.prepare(url)) }
            model.send(files: files)
        }
    }

    private func subtitle(for chat: Chat, now: Date) -> String {
        if let activity = model.activityText(for: chat.id) { return activity }
        if chat.isSavedMessages { return "your cloud notes" }
        if chat.isServiceAccount { return "service notifications" }
        if chat.isBot {
            return chat.botActiveUsers > 0 ? "bot · \(chat.botActiveUsers.formatted()) monthly users" : "bot"
        }
        switch chat.kind {
        case .privateChat, .secret: return PresenceFormatter.describe(chat.presence, now: now) ?? ""
        case .basicGroup, .supergroup:
            return chat.memberCount > 0 ? "\(chat.memberCount.formatted()) members" : "group"
        case .channel:
            return chat.memberCount > 0 ? "\(chat.memberCount.formatted()) subscribers" : "channel"
        }
    }
}

// MARK: - Header

/// Telegram-style header. macOS shows only one toolbar title in a three-column
/// window, so the chat's name and presence get a bar of their own.
private struct ConversationHeader: View {
    let chat: Chat
    let subtitle: String
    let isActivity: Bool

    var body: some View {
        HStack(spacing: 11) {
            Avatar(
                title: chat.title,
                seed: chat.id.rawValue,
                size: 36,
                imagePath: chat.avatarPath,
                thumbnail: chat.avatarThumbnail,
                isOnline: chat.presence == .online,
                isSavedMessages: chat.isSavedMessages
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(chat.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if chat.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                    if chat.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(isActivity || chat.presence == .online
                                         ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: subtitle)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Timeline

private struct MessageTimeline: View {
    let model: AppModel
    let chat: Chat

    @State private var isNearBottom = true
    /// False until the first page has been scrolled to the bottom. Paging is
    /// held off until then, because before positioning the view sits at the
    /// top — which would otherwise immediately trigger "load older".
    @State private var isPositioned = false
    private let bottomID = "timeline-bottom"

    private var isGroup: Bool {
        switch chat.kind {
        case .basicGroup, .supergroup: return true
        default: return false
        }
    }

    var body: some View {
        let rows = TimelineRow.build(from: model.messages, groupChat: isGroup)
        // Read receipts mean nothing in Saved Messages — nobody else reads it.
        let lastOutgoingID = chat.isSavedMessages ? nil
            : model.messages.last(where: { $0.isOutgoing && !$0.isService && !$0.isDeleted })?.id

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.isLoadingHistory, !model.messages.isEmpty {
                        ProgressView().controlSize(.small).padding(.vertical, 12)
                    }

                    ForEach(rows) { row in
                        switch row.kind {
                        case .day(let date):
                            DaySeparator(date: date)
                        case .service(let message):
                            ServiceLine(message: message)
                        case .message(let message, let position):
                            MessageRow(
                                model: model,
                                message: message,
                                position: position,
                                showsSender: isGroup,
                                showsReadLabel: message.id == lastOutgoingID,
                                showsReceipts: !chat.isSavedMessages
                            )
                            .id(message.id)
                            .onAppear { model.ensureReadDate(for: message) }
                        case .album(let items, let position):
                            let anchor = items.first { !$0.text.isEmpty } ?? items[0]
                            MessageRow(
                                model: model,
                                message: anchor,
                                position: position,
                                showsSender: isGroup,
                                showsReadLabel: items.contains { $0.id == lastOutgoingID },
                                showsReceipts: !chat.isSavedMessages,
                                album: items
                            )
                            .id(items[0].id)
                            .onAppear { model.ensureReadDate(for: items[items.count - 1]) }
                        }
                    }

                    if !model.hasNewerHistory {
                        ForEach(model.sponsored) { item in
                            SponsoredBubble(model: model, item: item)
                        }
                    }

                    Color.clear.frame(height: 8).id(bottomID)
                        // Precise, unlike content-size arithmetic: LazyVStack
                        // only estimates the height of rows it has not built.
                        .onScrollVisibilityChange(threshold: 0.01) { visible in
                            isNearBottom = visible
                            if visible, model.hasNewerHistory { model.loadNewerMessages() }
                        }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            }
            .defaultScrollAnchor(.bottom)
            .background { ChatWallpaper() }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < 280
            } action: { wasNearTop, nearTop in
                // Edge-triggered: only on *entering* the top region, so a page
                // landing above the viewport cannot trigger the next one.
                if isPositioned, nearTop, !wasNearTop {
                    model.loadOlderMessages()
                }
            }
            // First page arrived: settle at the newest message, then allow paging.
            .onChange(of: model.messages.isEmpty) { _, isEmpty in
                guard !isEmpty, !isPositioned else { return }
                proxy.scrollTo(bottomID, anchor: .bottom)
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(bottomID, anchor: .bottom)
                    isPositioned = true
                }
            }
            .onAppear {
                if !model.messages.isEmpty, !isPositioned {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        isPositioned = true
                    }
                }
            }
            // Follow new messages only when already at the bottom, or when the
            // user sent it — never yank someone out of older history.
            .onChange(of: model.messages.last?.id) { _, _ in
                guard isPositioned, let last = model.messages.last else { return }
                if isNearBottom || (last.isOutgoing && last.isPending) {
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
            }
            // A jump (reply, search, notification) brings the message into view.
            .onChange(of: model.highlightedMessageID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
            // Older history was prepended: keep the message the user was
            // reading exactly where it was.
            .onChange(of: model.messages.first?.id) { old, new in
                guard isPositioned, let old, let new, new.rawValue < old.rawValue else { return }
                proxy.scrollTo(old, anchor: .top)
            }
            .overlay {
                if model.messages.isEmpty {
                    if model.isLoadingHistory {
                        ProgressView().controlSize(.small)
                    } else if model.conversationError == nil {
                        EmptyStateView(
                            icon: "text.bubble",
                            title: "No messages yet",
                            message: "Say hello — your first message appears here."
                        )
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if (!isNearBottom && isPositioned) || model.hasNewerHistory {
                    Button {
                        if model.hasNewerHistory { model.returnToLatest(); return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().stroke(.separator, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.15), radius: 5, y: 1)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .help("Jump to latest")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast, model.viewerMessageID == nil {
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .padding(.bottom, 14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.toast)
        }
    }
}

/// Every version of an edited message that this Mac saw, original first.
struct EditHistoryView: View {
    let model: AppModel
    let message: Message

    @State private var versions: [MessageArchive.Version]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Edit history", systemImage: "clock.arrow.circlepath").font(.headline)
            if let versions {
                if versions.count < 2 {
                    Text(model.keepsDeletedMessages
                         ? "No earlier version was seen on this Mac — it was edited before Nodogram received it."
                         : "Turn on “Keep messages others delete” in Settings → Nodogram Features to keep edit history.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 300, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(versions.enumerated()), id: \.offset) { index, version in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(index == 0 ? "Original · \(RelativeTimeFormatter.exact(version.date))"
                                                    : "Edit \(index) · \(RelativeTimeFormatter.exact(version.date))")
                                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                                    Text(version.text.isEmpty ? "(no text)" : version.text)
                                        .font(.system(size: 12.5)).textSelection(.enabled)
                                        .strikethrough(index < versions.count - 1, color: .secondary.opacity(0.4))
                                }
                            }
                        }
                    }
                    .frame(width: 320)
                    .frame(maxHeight: 360)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .task { versions = await model.editHistory(of: message) }
    }
}

/// The chat background chosen in Settings → Appearance.
struct ChatWallpaper: View {
    @AppStorage(Theme.wallpaperKey) private var index = 0

    var body: some View {
        let colors = Theme.wallpapers[Theme.wallpapers.indices.contains(index) ? index : 0].colors
        if colors.isEmpty {
            Color.clear
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - Rows

struct GroupPosition: Equatable {
    var isFirst: Bool
    var isLast: Bool
}

struct TimelineRow: Identifiable {
    enum Kind {
        case day(Date)
        case service(Message)
        case message(Message, GroupPosition)
        /// Photos and videos sent as one album. The first message carrying a
        /// caption anchors the bubble.
        case album([Message], GroupPosition)
    }

    let id: String
    let kind: Kind

    /// Day separators, then runs: consecutive messages from one sender, on one
    /// day, within five minutes, render as a tight group.
    static func build(from messages: [Message], groupChat: Bool) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        rows.reserveCapacity(messages.count + 8)
        let calendar = Calendar.current
        var lastDay: Date?

        func sameRun(_ a: Message, _ b: Message) -> Bool {
            guard !a.isService, !b.isService, a.isOutgoing == b.isOutgoing else { return false }
            guard calendar.isDate(a.date, inSameDayAs: b.date) else { return false }
            guard abs(b.date.timeIntervalSince(a.date)) < 300 else { return false }
            return a.isOutgoing || (a.senderID == b.senderID && a.senderName == b.senderName)
        }

        func isAlbumMedia(_ m: Message) -> Bool {
            guard m.albumID != 0, !m.isDeleted else { return false }
            switch m.media {
            case .photo, .video, .animation: return true
            default: return false
            }
        }

        var index = 0
        while index < messages.count {
            let message = messages[index]
            defer { index += 1 }
            let day = calendar.startOfDay(for: message.date)
            if day != lastDay {
                rows.append(TimelineRow(id: "day-\(day.timeIntervalSince1970)", kind: .day(day)))
                lastDay = day
            }
            if message.isService {
                rows.append(TimelineRow(id: "svc-\(message.id.rawValue)", kind: .service(message)))
                continue
            }
            let previous = index > 0 ? messages[index - 1] : nil

            if isAlbumMedia(message) {
                var end = index
                while end + 1 < messages.count, messages[end + 1].albumID == message.albumID,
                      isAlbumMedia(messages[end + 1]) { end += 1 }
                if end > index {
                    let items = Array(messages[index...end])
                    let next = end + 1 < messages.count ? messages[end + 1] : nil
                    let position = GroupPosition(
                        isFirst: previous.map { !sameRun($0, message) } ?? true,
                        isLast: next.map { !sameRun(items[items.count - 1], $0) } ?? true)
                    rows.append(TimelineRow(id: "album-\(message.albumID)-\(message.id.rawValue)",
                                            kind: .album(items, position)))
                    index = end
                    continue
                }
            }

            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let position = GroupPosition(
                isFirst: previous.map { !sameRun($0, message) } ?? true,
                isLast: next.map { !sameRun(message, $0) } ?? true)
            rows.append(TimelineRow(id: "msg-\(message.id.rawValue)", kind: .message(message, position)))
        }
        return rows
    }
}

struct DaySeparator: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityAddTraits(.isHeader)
    }

    private var label: String { Self.label(for: date) }

    static func label(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }
        return date.formatted(.dateTime.year().month(.wide).day())
    }
}

struct ServiceLine: View {
    let message: Message

    var body: some View {
        let actor = message.isOutgoing ? "You" : message.senderName
        Text([actor, message.text].filter { !$0.isEmpty }.joined(separator: " "))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .help(RelativeTimeFormatter.exact(message.date))
    }
}

struct MessageRow: View {
    let model: AppModel
    let message: Message
    let position: GroupPosition
    let showsSender: Bool
    let showsReadLabel: Bool
    let showsReceipts: Bool
    var album: [Message] = []

    private var showsAvatarColumn: Bool { showsSender && !message.isOutgoing }

    private var isSelected: Bool { model.selectedMessageIDs.contains(message.id) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if model.isSelecting, !message.isDeleted {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
            }
            content
        }
        .contentShape(Rectangle())
        .overlay {
            // In selection mode a click anywhere on the row toggles it.
            if model.isSelecting, !message.isDeleted {
                Color.clear.contentShape(Rectangle()).onTapGesture { model.toggleSelection(message) }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.accent.opacity(model.highlightedMessageID == message.id || isSelected ? 0.12 : 0))
                .padding(.horizontal, -8)
                .animation(.easeOut(duration: 0.3), value: model.highlightedMessageID)
        )
        .onAppear { model.ensureReplyPreview(for: message) }
    }

    private var content: some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 8) {
                if message.isOutgoing { Spacer(minLength: 60) }

                if showsAvatarColumn {
                    if position.isLast {
                        Avatar(title: message.senderName, seed: message.senderID?.rawValue ?? 0, size: 30)
                    } else {
                        Color.clear.frame(width: 30, height: 1)
                    }
                }

                MessageBubble(
                    model: model,
                    message: message,
                    position: position,
                    showsSenderName: showsSender && !message.isOutgoing && position.isFirst,
                    showsReceipt: showsReceipts,
                    album: album
                )

                // Channel posts carry a one-click forward button, as in Telegram.
                if message.isChannelPost, message.canBeSaved, !message.isDeleted, !model.isSelecting {
                    Button {
                        model.forward(album.isEmpty ? [message] : album)
                    } label: {
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Forward")
                }

                if !message.isOutgoing { Spacer(minLength: 60) }
            }

            if showsReadLabel {
                ReadReceiptLabel(message: message, style: .detailed)
                    .padding(.trailing, 4)
            }
        }
        .padding(.top, position.isFirst ? 8 : 2)
    }
}

struct MessageBubble: View {
    let model: AppModel
    let message: Message
    let position: GroupPosition
    let showsSenderName: Bool
    let showsReceipt: Bool
    var album: [Message] = []

    @State private var spoilersRevealed = false
    @State private var showsTranslation = false
    @State private var deleteOptions: TelegramGateway.MessagePermissions?
    @State private var confirmingDelete = false
    @State private var showsEditHistory = false

    /// Media that looks best edge-to-edge, without bubble padding around it.
    /// Posts with reactions, comments or a quote keep their bubble so those
    /// have somewhere to sit.
    private var isBareMedia: Bool {
        guard message.text.isEmpty, !message.isDeleted, let media = message.media,
              message.reactions.isEmpty, commentsAnchor == nil, message.forwardedFrom == nil,
              message.replyToMessageID == nil else { return false }
        if !album.isEmpty { return true }
        switch media {
        case .photo, .video, .animation, .videoNote, .sticker: return true
        default: return false
        }
    }

    private var shape: UnevenRoundedRectangle {
        // The corner nearest the sender tightens on the last message of a run.
        let big: CGFloat = 16, small: CGFloat = 5
        return message.isOutgoing
            ? UnevenRoundedRectangle(topLeadingRadius: big, bottomLeadingRadius: big,
                                     bottomTrailingRadius: position.isLast ? small : big,
                                     topTrailingRadius: position.isFirst ? big : small)
            : UnevenRoundedRectangle(topLeadingRadius: position.isFirst ? big : small,
                                     bottomLeadingRadius: position.isLast ? small : big,
                                     bottomTrailingRadius: big, topTrailingRadius: big)
    }

    var body: some View {
        Group {
            if isBareMedia, let media = message.media {
                bareMedia(media)
            } else {
                bubble
            }
        }
        .opacity(message.isPending ? 0.75 : 1)
        .contextMenu {
            MessageMenu(model: model, message: message, reactions: model.chatReactions,
                        onTranslate: { showsTranslation = true },
                        onDelete: prepareDelete)
        }
        .popover(isPresented: $showsTranslation, arrowEdge: .trailing) {
            TranslationPopover(model: model, message: message)
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            if let options = deleteOptions {
                if options.canDeleteForEveryone {
                    Button(isChannel ? "Delete" : "Delete for Everyone", role: .destructive) {
                        model.delete([message], forEveryone: true)
                    }
                }
                if options.canDeleteForSelf {
                    Button("Delete for Me", role: .destructive) { model.delete([message], forEveryone: false) }
                }
            }
        } message: {
            Text(deleteOptions?.canDeleteForEveryone == true && !isChannel
                 ? "Deleting for everyone removes it from the chat for all members."
                 : "This can't be undone.")
        }
    }

    /// In an album only one message carries the discussion thread.
    private var commentsAnchor: Message? {
        message.commentCount != nil ? message : album.first { $0.commentCount != nil }
    }

    private var isChannel: Bool {
        if case .channel = model.chatsByID[message.chatID]?.kind { return true }
        return false
    }

    private var deleteTitle: String { "Delete this message?" }

    private func prepareDelete() {
        Task {
            guard let options = await model.permissions(for: message),
                  options.canDeleteForEveryone || options.canDeleteForSelf else {
                model.showToast("You can't delete this message.")
                return
            }
            deleteOptions = options
            confirmingDelete = true
        }
    }

    private var bubble: some View {
        BubbleLayout(maxWidth: 480) {
            if message.isDeleted, let deletedAt = message.deletedAt {
                Label("Deleted \(RelativeTimeFormatter.short(deletedAt)) · kept on this Mac", systemImage: "trash.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.failure)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.failure.opacity(0.12), in: Capsule())
                    .help("The sender deleted this \(RelativeTimeFormatter.exact(deletedAt)). It is gone from Telegram; this copy exists only here.")
            }
            if showsSenderName, !message.senderName.isEmpty {
                Text(message.senderName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.senderColor(for: message.senderID?.rawValue ?? 0))
                    .lineLimit(1)
            }

            if let origin = message.forwardedFrom {
                ForwardedHeader(origin: origin)
            }

            if let preview = model.replyPreview(for: message) {
                ReplyQuote(preview: preview) { model.jump(to: preview.messageID) }
            }

            if let poll = message.poll, !message.isDeleted {
                PollView(
                    poll: poll,
                    isOutgoing: message.isOutgoing,
                    onVote: { model.vote($0, in: message) },
                    onRetract: { model.retractVote(in: message) })
            } else if message.isDeleted, let label = message.attachmentLabel {
                Label(label, systemImage: label == "Poll" || label == "Quiz" ? "chart.bar" : "paperclip")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            } else if !album.isEmpty {
                AlbumGrid(messages: album, model: model, width: 432)
                    .padding(.horizontal, -6)
                    .padding(.top, 2)
            } else if let media = message.media {
                MessageMediaView(message: message, media: media, model: model)
                    .padding(.top, 2)
            } else if let label = message.attachmentLabel {
                AttachmentChip(label: label)
            }

            if !message.text.isEmpty, message.poll == nil || message.isDeleted {
                Text(FormattedText.attributed(message.text, entities: message.entities, baseSize: Theme.messageSize))
                    .font(.system(size: Theme.messageSize))
                    .foregroundStyle(message.isDeleted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        LinkPolicy.open(url)
                        return .handled
                    })
                    .overlay {
                        if FormattedText.hasSpoiler(message.entities), !spoilersRevealed {
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { withAnimation { spoilersRevealed = true } }
                                .help("Click to reveal")
                        }
                    }
            }

            if !message.reactions.isEmpty, !message.isDeleted {
                ReactionsBar(model: model, message: message)
            }

            if let post = commentsAnchor, let count = post.commentCount, !message.isDeleted {
                Divider().padding(.horizontal, -12)
                CommentsBar(count: count, commenters: post.recentCommenters) { model.openComments(for: post) }
            }

            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(fill, in: shape)
        .overlay {
            if message.isDeleted {
                shape.strokeBorder(Theme.failure.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    private var fill: AnyShapeStyle {
        if message.isDeleted { return AnyShapeStyle(Theme.failure.opacity(0.07)) }
        return message.isOutgoing ? AnyShapeStyle(Theme.bubbleOutgoing) : AnyShapeStyle(Theme.bubbleIncoming)
    }

    /// Photos, videos, round videos and stickers sit without a bubble; the
    /// time floats over the corner like Telegram's.
    private func bareMedia(_ media: MessageMedia) -> some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
            if showsSenderName, !message.senderName.isEmpty {
                Text(message.senderName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.senderColor(for: message.senderID?.rawValue ?? 0))
                    .padding(.leading, 4)
            }
            Group {
                if album.isEmpty {
                    MessageMediaView(message: message, media: media, model: model)
                } else {
                    AlbumGrid(messages: album, model: model)
                }
            }
                .overlay(alignment: .bottomTrailing) {
                    footer
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(7)
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if message.isDeleted, let deletedAt = message.deletedAt {
                Image(systemName: "trash")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("Deleted · \(deletedAt.formatted(.dateTime.hour().minute()))")
                    .help("""
                        Deleted by the sender \(RelativeTimeFormatter.exact(deletedAt)). \
                        This copy exists only on this Mac — it is gone from Telegram.
                        """)
            } else if message.wasEdited {
                Button { showsEditHistory = true } label: {
                    Text(L10n.edited.lowercased()).underline(false)
                }
                .buttonStyle(.plain)
                .help("Show earlier versions")
                .popover(isPresented: $showsEditHistory, arrowEdge: .bottom) {
                    EditHistoryView(model: model, message: message)
                }
            }
            if message.isChannelPost, !message.authorSignature.isEmpty {
                Text(message.authorSignature).lineLimit(1)
            }
            if message.viewCount > 0 {
                Image(systemName: "eye").font(.system(size: 9.5))
                Text(message.viewCount >= 1000
                     ? message.viewCount.formatted(.number.notation(.compactName))
                     : "\(message.viewCount)")
                    .help("\(message.viewCount.formatted()) views")
            }
            Text(message.date.formatted(.dateTime.hour().minute()))
                .help(RelativeTimeFormatter.exact(message.date))
            if message.isOutgoing, !message.isDeleted, showsReceipt {
                ReadReceiptLabel(message: message, style: .compact)
            }
        }
        .font(.system(size: 10.5).monospacedDigit())
        .foregroundStyle(message.isDeleted ? AnyShapeStyle(Theme.failure) : AnyShapeStyle(.secondary))
    }
}

/// For content that has no richer view (polls, locations, unsupported types).
private struct AttachmentChip: View {
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        let lower = label.lowercased()
        if lower == "location" { return "mappin.and.ellipse" }
        if lower == "contact" { return "person.crop.circle" }
        if lower == "poll" { return "chart.bar.xaxis" }
        if lower.hasPrefix("call") || lower.hasPrefix("video call") { return "phone" }
        if lower == "story" { return "circle.dashed" }
        if lower == "checklist" { return "checklist" }
        if lower.contains("expired") { return "timer" }
        if lower.contains("unsupported") || lower.contains("not supported") { return "questionmark.square.dashed" }
        return "doc"
    }
}

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: onDismiss).buttonStyle(.borderless).font(.system(size: 12))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.warning.opacity(0.1))
        .overlay(alignment: .top) { Divider() }
    }
}
