//  Message and chat actions: reply, edit, delete, forward, react, links,
//  translation, multi-select, jumping, comments, sponsored messages.
//
//  Kept apart from AppModel.swift so each area of behaviour has its own home,
//  as the audit recommended for the oversized model.

import AppKit
import Foundation
import NodogramDomain
import NodogramTelegram
import NodogramPlatform

public struct ForwardRequest: Identifiable, Equatable {
    public let id = UUID()
    public let sourceChat: ChatID
    public let messageIDs: [MessageID]
    /// Whether any message has a caption, so the "captions" option is relevant.
    public let hasCaptions: Bool
}

public struct CommentsState: Equatable {
    public let postChatID: ChatID
    public let postMessageID: MessageID
    public var discussionChatID: ChatID?
    public var threadID: Int64?
    public var messages: [Message] = []
    public var isLoading = true
    public var error: String?
    public var draft = ""
    public var replyTo: Message?
}

public struct ConversationSearchState: Equatable {
    public var query = ""
    public var results: [Message] = []
    public var index = 0
    public var isSearching = false
}

public struct StoryViewerState: Equatable {
    public var owners: [ChatID]
    public var ownerIndex: Int
    public var storyIndex: Int
}

extension AppModel {

    // MARK: - Interaction updates

    func applyInteraction(chatID: ChatID, messageID: MessageID, views: Int, forwards: Int,
                          reactions: [ReactionSummary], comments: Int?) {
        func patch(_ message: inout Message) {
            message.viewCount = views
            message.forwardCount = forwards
            message.reactions = reactions
            if let comments { message.commentCount = comments }
        }
        if chatID == selectedChatID, let index = messages.firstIndex(where: { $0.id == messageID }) {
            patch(&messages[index])
        }
        if var state = self.comments, state.discussionChatID == chatID,
           let index = state.messages.firstIndex(where: { $0.id == messageID }) {
            patch(&state.messages[index])
            self.comments = state
        }
    }

    // MARK: - Reply / edit

    public func reply(to message: Message) {
        composerMode = .replying(message)
    }

    public func edit(_ message: Message) {
        composerMode = .editing(message)
        draftText = message.text
    }

    public func cancelComposerMode() {
        if case .editing = composerMode { draftText = "" }
        composerMode = .normal
    }

    /// Sends, replies or saves an edit depending on the composer's mode.
    public func submitComposer() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let gateway, let chatID = selectedChatID else { return }
        let mode = composerMode
        composerMode = .normal

        if case .editing(let original) = mode {
            draftText = ""
            Task { [weak self] in
                do { try await gateway.editText(original.id, in: chatID, text: text) }
                catch { self?.showToast(Self.describe(error)); self?.draftText = text; self?.composerMode = mode }
            }
            return
        }

        var replyTo: MessageID?
        if case .replying(let target) = mode { replyTo = target.id }
        draftText = ""
        draftIndicatorVisible = false
        Task { [weak self] in
            do {
                try await gateway.sendText(text, to: chatID, replyTo: replyTo)
            } catch {
                guard let self else { return }
                if self.selectedChatID == chatID, self.draftText.isEmpty { self.draftText = text }
                self.showToast(Self.describe(error))
            }
        }
    }

    // MARK: - Delete

    public func permissions(for message: Message) async -> TelegramGateway.MessagePermissions? {
        await gateway?.permissions(for: message.id, in: message.chatID)
    }

    public func delete(_ messages: [Message], forEveryone: Bool) {
        guard let gateway, let chatID = messages.first?.chatID else { return }
        for message in messages { selfDeletedKeys.insert("\(chatID.rawValue)-\(message.id.rawValue)") }
        Task { [weak self] in
            do {
                try await gateway.deleteMessages(messages.map(\.id), in: chatID, forEveryone: forEveryone)
                self?.endSelection()
            } catch {
                self?.showToast(Self.describe(error))
            }
        }
    }

    // MARK: - Forward

    public func forward(_ messages: [Message]) {
        guard let first = messages.first else { return }
        guard messages.allSatisfy(\.canBeSaved) else {
            showToast("This chat doesn't allow forwarding.")
            return
        }
        forwardRequest = ForwardRequest(
            sourceChat: first.chatID,
            messageIDs: messages.map(\.id).sorted { $0.rawValue < $1.rawValue },
            hasCaptions: messages.contains { $0.media != nil && !$0.text.isEmpty })
    }

    public func completeForward(_ request: ForwardRequest, to targets: [ChatID], options: ForwardOptions) {
        guard let gateway, !targets.isEmpty else { return }
        forwardRequest = nil
        Task { [weak self] in
            do {
                try await gateway.forward(request.messageIDs, from: request.sourceChat, to: targets, options: options)
                let names = targets.compactMap { self?.chatsByID[$0]?.title }
                self?.showToast(names.count == 1 ? "Forwarded to \(names[0])" : "Forwarded to \(targets.count) chats")
                self?.endSelection()
            } catch {
                self?.showToast(Self.describe(error))
            }
        }
    }

    // MARK: - Links, copy, translate

    public func copyLink(to message: Message) {
        guard let gateway else { return }
        Task { [weak self] in
            if let link = await gateway.messageLink(message.id, in: message.chatID) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                self?.showToast("Link copied")
            } else {
                self?.showToast("Links are available only in channels and public groups.")
            }
        }
    }

    public func copyText(of messages: [Message]) {
        let text = messages.sorted { $0.id.rawValue < $1.id.rawValue }
            .map { messages.count > 1 ? "\($0.senderName.isEmpty ? "" : "\($0.senderName): ")\($0.text)" : $0.text }
            .joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast(messages.count > 1 ? "\(messages.count) messages copied" : "Copied")
    }

    /// Translates into the Mac's preferred language.
    public func translate(_ message: Message) async -> String? {
        let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return await gateway?.translate(message.text, to: language)
    }

    // MARK: - Reactions

    public func toggleReaction(_ kind: ReactionSummary.Kind, on message: Message) {
        guard let gateway else { return }
        let isChosen = message.reactions.contains { $0.kind == kind && $0.isChosen }
        Task { [weak self] in
            do { try await gateway.setReaction(kind, on: message.id, in: message.chatID, add: !isChosen) }
            catch { self?.showToast(Self.describe(error)) }
        }
    }

    public func availableReactions(for message: Message) async -> [ReactionSummary.Kind] {
        await gateway?.availableReactions(for: message.id, in: message.chatID) ?? []
    }

    /// Downloads a custom emoji's still image once, as reactions come into view.
    public func ensureCustomEmoji(_ id: Int64) {
        guard let gateway, customEmoji[id] == nil, requestedCustomEmoji.insert(id).inserted else { return }
        Task { [weak self] in
            if let file = await gateway.customEmojiImage(id), let path = file.localPath {
                self?.customEmoji[id] = path
            }
        }
    }

    // MARK: - Selection

    public func beginSelection(with message: Message) {
        isSelecting = true
        selectedMessageIDs = [message.id]
    }

    public func toggleSelection(_ message: Message) {
        if selectedMessageIDs.contains(message.id) { selectedMessageIDs.remove(message.id) }
        else { selectedMessageIDs.insert(message.id) }
        if selectedMessageIDs.isEmpty { isSelecting = false }
    }

    public func endSelection() {
        isSelecting = false
        selectedMessageIDs = []
    }

    public var selectedMessages: [Message] {
        messages.filter { selectedMessageIDs.contains($0.id) }
    }

    // MARK: - Jumping

    /// Scrolls to a message, loading the history around it when needed.
    public func jump(to messageID: MessageID, in chatID: ChatID? = nil) {
        let chatID = chatID ?? selectedChatID
        guard let chatID else { return }
        if chatID != selectedChatID {
            select(chatID)
            pendingJumpID = messageID
        }
        if messages.contains(where: { $0.id == messageID }) {
            highlight(messageID)
            return
        }
        guard let gateway else { return }
        isLoadingHistory = true
        Task { [weak self] in
            let around = (try? await gateway.history(around: messageID, in: chatID)) ?? []
            guard let self, self.selectedChatID == chatID else { return }
            self.isLoadingHistory = false
            let wasPending = self.pendingJumpID == messageID
            self.pendingJumpID = nil
            guard !around.isEmpty else {
                self.showToast("That message is no longer available.")
                // Fall back to the latest page rather than an empty chat.
                if wasPending { self.reloadLatest() }
                return
            }
            // Deleted messages kept on this Mac belong in place, so a jump to
            // one from the Deleted section lands on it.
            self.messages = await self.mergingDeleted(into: around, chatID: chatID, openEnded: false)
            self.hasMoreHistory = true
            self.hasNewerHistory = true
            self.highlight(messageID)
        }
    }

    private func highlight(_ id: MessageID) {
        highlightedMessageID = id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            if self?.highlightedMessageID == id { self?.highlightedMessageID = nil }
        }
    }

    /// Loads newer messages after a jump into older history.
    public func loadNewerMessages() {
        guard let gateway, let chatID = selectedChatID, hasNewerHistory, !isLoadingHistory,
              let newest = messages.last else { return }
        isLoadingHistory = true
        Task { [weak self] in
            let newer = (try? await gateway.history(after: newest.id, in: chatID)) ?? []
            guard let self, self.selectedChatID == chatID else { return }
            let known = Set(self.messages.map(\.id))
            self.messages += newer.filter { !known.contains($0.id) }
            self.hasNewerHistory = !newer.isEmpty
            self.isLoadingHistory = false
        }
    }

    /// Returns to the newest messages (the ⌄ button after a jump).
    public func returnToLatest() {
        guard hasNewerHistory, let chatID = selectedChatID else { return }
        let id = chatID
        selectedChatIDForReload(id)
    }

    private func selectedChatIDForReload(_ chatID: ChatID) {
        select(nil)
        select(chatID)
    }

    func reloadLatest() {
        guard let chatID = selectedChatID else { return }
        selectedChatIDForReload(chatID)
    }

    // MARK: - Replies

    /// The quote shown above a reply.
    public func replyPreview(for message: Message) -> ReplyPreview? {
        if let preview = message.replyPreview, !preview.senderName.isEmpty || message.replyToMessageID == nil {
            return preview
        }
        guard let id = message.replyToMessageID else { return message.replyPreview }
        if let original = messages.first(where: { $0.id == id }) ?? comments?.messages.first(where: { $0.id == id }) {
            return ReplyPreview(messageID: id,
                                senderName: original.isOutgoing ? "You" : original.senderName,
                                text: original.text.isEmpty ? (original.attachmentLabel ?? "") : original.text)
        }
        return replyPreviews[id] ?? message.replyPreview
    }

    public func ensureReplyPreview(for message: Message) {
        guard let gateway, let id = message.replyToMessageID,
              !messages.contains(where: { $0.id == id }), replyPreviews[id] == nil,
              requestedReplies.insert(id).inserted else { return }
        Task { [weak self] in
            guard let original = await gateway.repliedMessage(to: message.id, in: message.chatID) else { return }
            self?.replyPreviews[id] = ReplyPreview(
                messageID: id, senderName: original.isOutgoing ? "You" : original.senderName,
                text: original.text.isEmpty ? (original.attachmentLabel ?? "") : original.text)
        }
    }

    // MARK: - Comments

    public func openComments(for post: Message) {
        guard let gateway else { return }
        var state = CommentsState(postChatID: post.chatID, postMessageID: post.id)
        comments = state
        Task { [weak self] in
            do {
                let thread = try await gateway.commentThread(for: post.id, in: post.chatID)
                let loaded = try await gateway.comments(on: post.id, in: post.chatID)
                guard let self, self.comments?.postMessageID == post.id else { return }
                state.discussionChatID = thread.chatID
                state.threadID = thread.threadID
                // The thread's first message is the post itself, mirrored into
                // the discussion group; it is shown separately, not as a comment.
                state.messages = loaded.filter { $0.id.rawValue != thread.threadID }
                state.isLoading = false
                self.comments = state
                await gateway.ensureChat(thread.chatID)
            } catch {
                guard let self, self.comments?.postMessageID == post.id else { return }
                state.isLoading = false
                state.error = Self.describe(error)
                self.comments = state
            }
        }
    }

    public func closeComments() {
        comments = nil
    }

    public func setCommentDraft(_ text: String) {
        comments?.draft = text
    }

    public func replyInComments(to message: Message?) {
        comments?.replyTo = message
    }

    public func sendComment() {
        guard let gateway, var state = comments, let chat = state.discussionChatID, let thread = state.threadID else { return }
        let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let replyTo = state.replyTo?.id
        state.draft = ""
        state.replyTo = nil
        comments = state
        Task { [weak self] in
            do {
                try await gateway.sendText(text, to: chat, replyTo: replyTo, thread: thread)
            } catch {
                self?.comments?.draft = text
                self?.showToast(Self.describe(error))
            }
        }
    }

    func appendToCommentsIfNeeded(_ message: Message) {
        guard var state = comments, message.chatID == state.discussionChatID,
              message.threadID == state.threadID,
              message.id.rawValue != state.threadID,
              !state.messages.contains(where: { $0.id == message.id }) else { return }
        state.messages.append(message)
        state.messages.sort { $0.id.rawValue < $1.id.rawValue }
        comments = state
    }

    // MARK: - Sponsored messages

    /// Fetches ads when a channel opens, cached for five minutes as Telegram's
    /// documentation requires.
    func loadSponsored(for chatID: ChatID) {
        guard let gateway, let chat = chatsByID[chatID], case .channel = chat.kind else {
            sponsored = []
            return
        }
        if let fetched = sponsoredFetchedAt[chatID], Date().timeIntervalSince(fetched) < 300 { return }
        sponsoredFetchedAt[chatID] = Date()
        Task { [weak self] in
            let result = await gateway.sponsoredMessages(in: chatID)
            guard self?.selectedChatID == chatID else { return }
            self?.sponsored = result.items
        }
    }

    public func sponsoredBecameVisible(_ item: SponsoredItem) {
        guard let gateway, let chatID = selectedChatID, sponsoredViewed.insert(item.id).inserted else { return }
        Task { await gateway.markSponsoredViewed(item.id, in: chatID) }
    }

    public func openSponsored(_ item: SponsoredItem, mediaClick: Bool = false) {
        guard let gateway, let chatID = selectedChatID else { return }
        Task { await gateway.clickSponsored(item.id, in: chatID, media: mediaClick) }
        if let url = LinkPolicy.safeURL(item.url) { NSWorkspace.shared.open(url) }
    }

    // MARK: - Chat actions

    public func setMuted(_ muted: Bool, chat: ChatID) {
        perform { try await $0.setMuted(muted, chat: chat) }
    }

    public func setPinned(_ pinned: Bool, chat: ChatID) {
        perform { try await $0.setPinned(pinned, chat: chat) }
    }

    public func setMarkedUnread(_ unread: Bool, chat: ChatID) {
        perform { try await $0.setMarkedUnread(unread, chat: chat) }
    }

    public func setArchived(_ archived: Bool, chat: ChatID) {
        perform { try await $0.setArchived(archived, chat: chat) }
        showToast(archived ? "Chat archived" : "Chat moved to All Chats")
    }

    public func markAsRead(_ chat: ChatID) {
        guard let gateway, let last = chatsByID[chat]?.lastMessage else { return }
        Task {
            await gateway.markRead(chat, messages: [last.messageID])
            if self.chatsByID[chat]?.isMarkedAsUnread == true {
                try? await gateway.setMarkedUnread(false, chat: chat)
            }
        }
    }

    private func perform(_ work: @escaping @Sendable (TelegramGateway) async throws -> Void) {
        guard let gateway else { return }
        Task { [weak self] in
            do { try await work(gateway) } catch { self?.showToast(Self.describe(error)) }
        }
    }

    // MARK: - Files

    public func send(files: [OutgoingFile], caption: String = "") {
        guard let gateway, let chatID = selectedChatID, !files.isEmpty else { return }
        var replyTo: MessageID?
        if case .replying(let target) = composerMode { replyTo = target.id; composerMode = .normal }
        Task { [weak self] in
            for (index, file) in files.enumerated() {
                do {
                    try await gateway.sendFile(file, caption: index == 0 ? caption : "", to: chatID,
                                               replyTo: index == 0 ? replyTo : nil)
                } catch {
                    self?.showToast(Self.describe(error))
                }
            }
        }
    }
}
