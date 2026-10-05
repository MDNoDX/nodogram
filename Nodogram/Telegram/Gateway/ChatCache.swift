//  ChatCache — the client-side mirror of TDLib's chat state.
//
//  TDLib does not hand out a chat list. It sends `updateNewChat` once per chat
//  and then a stream of granular changes — a new title, a moved position, a new
//  last message — and expects the client to maintain the picture. This type is
//  that picture.
//
//  It is deliberately a plain "updates in, events out" unit with no networking,
//  so the logic that decides what the user sees can be tested by feeding it
//  decoded updates.
//
//  Thread safety: TDLibKit delivers updates on one serial queue, but request
//  paths (loading history, mapping a sent message) read the cache from other
//  threads, so every access goes through the lock.

import Foundation
import NodogramDomain
import TDLibKit

/// TDLibKit also declares a `Date` type; in this file `Date` always means Foundation's.
private typealias Date = Foundation.Date

final class ChatCache: @unchecked Sendable {

    /// Mutable mirror of one chat. TDLibKit's `Chat` is immutable, and granular
    /// updates must be applied in place, hence a record of our own.
    struct Record {
        var id: Int64
        var title: String
        var type: ChatType
        var photo: ChatPhotoInfo?
        var downloadedAvatarPath: String?
        var mainOrder: Int64 = 0
        var isPinnedInMain = false
        var archiveOrder: Int64 = 0
        var folderOrders: [Int: Int64] = [:]
        var folderPinned: Set<Int> = []
        var lastMessage: TDLibKit.Message?
        var unreadCount: Int
        var unreadMentionCount: Int
        var lastReadOutboxMessageId: Int64
        var muteFor: Int
        var isMarkedAsUnread: Bool
        var draftText: String?
        /// Kept whole so a mute toggle can resend every other setting unchanged.
        var notificationSettings: ChatNotificationSettings
        var hasProtectedContent: Bool
    }

    private struct GroupInfo {
        var status: ChatMemberStatus
        var memberCount: Int
        var isChannel: Bool
    }

    private let lock = NSLock()
    private var records: [Int64: Record] = [:]
    private var users: [Int64: TDLibKit.User] = [:]
    /// Last-seen (isContact, isMutualContact) per user, to spot changes.
    private var contactState: [Int64: (contact: Bool, mutual: Bool)] = [:]
    /// Kept apart from `users` because `updateUserStatus` arrives on its own and
    /// TDLibKit's `User` cannot be modified in place.
    private var statuses: [Int64: UserStatus] = [:]
    /// The signed-in user. Their chat with themselves is "Saved Messages".
    private var myUserId: Int64?
    private var supergroups: [Int64: GroupInfo] = [:]
    private var basicGroups: [Int64: GroupInfo] = [:]
    /// Telegram's id for its own service notifications account.
    private static let serviceAccountId: Int64 = 777000

    // MARK: - Applying updates

    /// Applies one update and returns the domain events it implies, in order.
    func apply(_ update: Update) -> [TelegramEvent] {
        lock.lock()
        defer { lock.unlock() }

        switch update {
        case .updateNewChat(let u):
            let chat = u.chat
            var record = Record(
                id: chat.id,
                title: chat.title,
                type: chat.type,
                photo: chat.photo,
                lastMessage: chat.lastMessage,
                unreadCount: chat.unreadCount,
                unreadMentionCount: chat.unreadMentionCount,
                lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                muteFor: chat.notificationSettings.muteFor,
                isMarkedAsUnread: chat.isMarkedAsUnread,
                draftText: Self.draftText(chat.draftMessage),
                notificationSettings: chat.notificationSettings,
                hasProtectedContent: chat.hasProtectedContent
            )
            Self.applyPositions(chat.positions, to: &record)
            records[chat.id] = record
            return [.chatUpdated(domainChat(record))]

        case .updateChatTitle(let u):
            return mutate(u.chatId) { $0.title = u.title }

        case .updateChatPhoto(let u):
            return mutate(u.chatId) {
                $0.photo = u.photo
                $0.downloadedAvatarPath = nil
            }

        case .updateChatPosition(let u):
            return mutate(u.chatId) { Self.applyPosition(u.position, to: &$0) }

        case .updateChatLastMessage(let u):
            return mutate(u.chatId) {
                $0.lastMessage = u.lastMessage
                Self.applyPositions(u.positions, to: &$0)
            }

        case .updateChatReadInbox(let u):
            return mutate(u.chatId) { $0.unreadCount = u.unreadCount }

        case .updateChatReadOutbox(let u):
            var events = mutate(u.chatId) { $0.lastReadOutboxMessageId = u.lastReadOutboxMessageId }
            events.append(.outboxRead(ChatID(u.chatId), upTo: MessageID(u.lastReadOutboxMessageId)))
            return events

        case .updateChatUnreadMentionCount(let u):
            return mutate(u.chatId) { $0.unreadMentionCount = u.unreadMentionCount }

        case .updateChatIsMarkedAsUnread(let u):
            return mutate(u.chatId) { $0.isMarkedAsUnread = u.isMarkedAsUnread }

        case .updateChatNotificationSettings(let u):
            return mutate(u.chatId) {
                $0.muteFor = u.notificationSettings.muteFor
                $0.notificationSettings = u.notificationSettings
            }

        case .updateChatHasProtectedContent(let u):
            return mutate(u.chatId) { $0.hasProtectedContent = u.hasProtectedContent }

        case .updateSupergroup(let u):
            let group = u.supergroup
            supergroups[group.id] = GroupInfo(status: group.status, memberCount: group.memberCount, isChannel: group.isChannel)
            return refreshChats { if case .chatTypeSupergroup(let t) = $0.type { return t.supergroupId == group.id }; return false }

        case .updateBasicGroup(let u):
            let group = u.basicGroup
            basicGroups[group.id] = GroupInfo(status: group.status, memberCount: group.memberCount, isChannel: false)
            return refreshChats { if case .chatTypeBasicGroup(let t) = $0.type { return t.basicGroupId == group.id }; return false }

        case .updateNotificationGroup(let u):
            var events: [TelegramEvent] = []
            let added: [ChatNotification] = u.addedNotifications.compactMap { notification in
                guard case .notificationTypeNewMessage(let n) = notification.type else { return nil }
                return ChatNotification(id: notification.id, groupID: u.notificationGroupId,
                                        chatID: ChatID(u.chatId), message: domainMessage(n.message),
                                        isSilent: notification.isSilent)
            }
            if !added.isEmpty { events.append(.notificationsAdded(added)) }
            if !u.removedNotificationIds.isEmpty {
                events.append(.notificationsRemoved(groupID: u.notificationGroupId, ids: u.removedNotificationIds))
            }
            return events

        case .updateChatDraftMessage(let u):
            return mutate(u.chatId) {
                $0.draftText = Self.draftText(u.draftMessage)
                Self.applyPositions(u.positions, to: &$0)
            }

        case .updateUser(let u):
            users[u.user.id] = u.user
            statuses[u.user.id] = u.user.status
            // In TDLib a private chat's id equals the user's id.
            var events = refreshPrivateChat(userId: u.user.id)
            if case .userTypeRegular = u.user.type {
                let identity = UserIdentity(name: Self.fullName(u.user),
                                            usernames: u.user.usernames?.activeUsernames ?? [], seenAt: Date())
                events.append(.userIdentity(UserID(u.user.id), identity))
                if let previous = contactState[u.user.id],
                   previous.mutual != u.user.isMutualContact || previous.contact != u.user.isContact {
                    events.append(.contactChanged(UserID(u.user.id), name: Self.fullName(u.user),
                                                  nowMutual: u.user.isMutualContact, wasMutual: previous.mutual,
                                                  isContact: u.user.isContact))
                }
                contactState[u.user.id] = (u.user.isContact, u.user.isMutualContact)
            }
            return events

        case .updateUserStatus(let u):
            statuses[u.userId] = u.status
            return refreshPrivateChat(userId: u.userId)

        case .updateNewMessage(let u):
            return [.messageAdded(domainMessage(u.message))]

        case .updateMessageSendSucceeded(let u):
            return [.messageReplaced(old: MessageID(u.oldMessageId), new: domainMessage(u.message))]

        case .updateMessageSendFailed(let u):
            var message = domainMessage(u.message)
            message.sendState = .failed(reason: u.error.message)
            return [.messageReplaced(old: MessageID(u.oldMessageId), new: message)]

        case .updateDeleteMessages(let u):
            // `fromCache` means TDLib merely evicted the messages from memory.
            // Treating that as a deletion would make messages vanish wrongly.
            guard u.isPermanent, !u.fromCache else { return [] }
            return [.messagesDeleted(ChatID(u.chatId), u.messageIds.map(MessageID.init))]

        case .updateMessageContent(let u):
            let mapped = ContentMapping.map(u.newContent)
            return [.messageContentChanged(
                ChatID(u.chatId), MessageID(u.messageId),
                text: mapped.text, attachmentLabel: mapped.attachmentLabel)]

        case .updateFile(let u):
            return [.fileUpdated(MediaMapping.file(u.file))]

        case .updatePoll(let u):
            // Votes, closing and quiz answers all arrive this way.
            return [.pollUpdated(PollMapping.map(u.poll, details: ""))]
        case .updateMessageInteractionInfo(let u):
            let info = interaction(u.interactionInfo, isChannelPost: nil)
            return [.messageInteraction(ChatID(u.chatId), MessageID(u.messageId),
                                        views: info.views, forwards: info.forwards,
                                        reactions: info.reactions, comments: info.comments)]

        case .updateChatActiveStories(let u):
            let stories = u.activeStories
            return [.storiesChanged(StoryOwner(
                chatID: ChatID(stories.chatId),
                storyIDs: stories.list == nil ? [] : stories.stories.map(\.storyId),
                maxReadStoryID: stories.maxReadStoryId,
                order: stories.order))]

        case .updateChatAction(let u):
            guard case .messageSenderUser(let sender) = u.senderId else { return [] }
            return [.chatActivity(ChatID(u.chatId), user: UserID(sender.userId), activity: Self.activity(u.action))]

        case .updateMessageEdited(let u):
            return [.messageEdited(
                ChatID(u.chatId), MessageID(u.messageId),
                editDate: Date(timeIntervalSince1970: TimeInterval(u.editDate)))]

        case .updateChatFolders(let u):
            let folders = u.chatFolders.map { info in
                ChatFolderSummary(id: info.id, title: info.name.text.text,
                                  iconName: info.icon.name, colorID: info.colorId)
            }
            return [.foldersChanged(folders, mainPosition: u.mainChatListPosition)]

        default:
            return []
        }
    }

    /// Records the signed-in user and returns their Saved Messages chat, now
    /// presented under that name, if it is already known.
    func setMyUserId(_ id: Int64) -> NodogramDomain.Chat? {
        lock.lock(); defer { lock.unlock() }
        myUserId = id
        return records[id].map(domainChat)
    }

    // MARK: - Reads

    func chat(_ id: Int64) -> NodogramDomain.Chat? {
        lock.lock(); defer { lock.unlock() }
        return records[id].map(domainChat)
    }

    func title(of chatId: Int64) -> String? {
        lock.lock(); defer { lock.unlock() }
        return records[chatId].map { $0.id == myUserId ? "Saved Messages" : $0.title }
    }

    func smallPhotoFileId(chatId: Int64) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard let record = records[chatId], record.downloadedAvatarPath == nil,
              let small = record.photo?.small else { return nil }
        if small.local.isDownloadingCompleted, !small.local.path.isEmpty { return nil }
        return small.id
    }

    /// Records a finished avatar download and returns the refreshed chat.
    func setAvatarPath(_ path: String, chatId: Int64) -> NodogramDomain.Chat? {
        lock.lock(); defer { lock.unlock() }
        guard var record = records[chatId] else { return nil }
        record.downloadedAvatarPath = path
        records[chatId] = record
        return domainChat(record)
    }

    func mapMessage(_ message: TDLibKit.Message) -> NodogramDomain.Message {
        lock.lock(); defer { lock.unlock() }
        return domainMessage(message)
    }

    // MARK: - Private: mutation helpers (lock already held)

    private func mutate(_ chatId: Int64, _ change: (inout Record) -> Void) -> [TelegramEvent] {
        // An update for a chat we have not seen yet is ignored rather than
        // guessed at: TDLib guarantees `updateNewChat` arrives first.
        guard var record = records[chatId] else { return [] }
        change(&record)
        records[chatId] = record
        return [.chatUpdated(domainChat(record))]
    }

    private func refreshChats(where matches: (Record) -> Bool) -> [TelegramEvent] {
        records.values.filter(matches).map { .chatUpdated(domainChat($0)) }
    }

    /// Groups and channels the user is in, from what TDLib already sent.
    func groupSummaries() -> [GroupSummary] {
        lock.lock(); defer { lock.unlock() }
        return records.values.compactMap { record -> GroupSummary? in
            let info: GroupInfo?
            switch record.type {
            case .chatTypeBasicGroup(let t): info = basicGroups[t.basicGroupId]
            case .chatTypeSupergroup(let t): info = supergroups[t.supergroupId]
            default: return nil
            }
            guard let info else { return nil }
            let role: GroupSummary.Role
            var canRemove = false
            switch info.status {
            case .chatMemberStatusCreator(let c) where c.isMember:
                role = .owner; canRemove = true
            case .chatMemberStatusAdministrator(let a):
                role = .admin; canRemove = a.rights.canRestrictMembers
            case .chatMemberStatusMember:
                role = .member
            case .chatMemberStatusRestricted(let r):
                role = r.isMember ? .member : .left
            case .chatMemberStatusLeft, .chatMemberStatusBanned:
                role = .left
            case .chatMemberStatusCreator:
                role = .left
            }
            return GroupSummary(id: ChatID(record.id), title: record.title, isChannel: info.isChannel,
                                role: role, memberCount: info.memberCount,
                                canRemoveMembers: canRemove && !info.isChannel)
        }
    }

    /// The basic group or supergroup id behind a chat.
    func groupIdentity(chatId: Int64) -> (basic: Int64?, supergroup: Int64?) {
        lock.lock(); defer { lock.unlock() }
        switch records[chatId]?.type {
        case .chatTypeBasicGroup(let t): return (t.basicGroupId, nil)
        case .chatTypeSupergroup(let t): return (nil, t.supergroupId)
        default: return (nil, nil)
        }
    }

    func user(_ id: Int64) -> TDLibKit.User? {
        lock.lock(); defer { lock.unlock() }
        return users[id]
    }

    func isContact(_ id: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return users[id]?.isContact ?? false
    }

    static func displayName(_ user: TDLibKit.User) -> String { fullName(user) }

    func notificationSettings(chatId: Int64) -> ChatNotificationSettings? {
        lock.lock(); defer { lock.unlock() }
        return records[chatId]?.notificationSettings
    }

    private func refreshPrivateChat(userId: Int64) -> [TelegramEvent] {
        guard var record = records[userId], case .chatTypePrivate = record.type else { return [] }
        if let user = users[userId] {
            let name = Self.fullName(user)
            if !name.isEmpty { record.title = name }
        }
        records[userId] = record
        return [.chatUpdated(domainChat(record))]
    }

    private static func applyPositions(_ positions: [ChatPosition], to record: inout Record) {
        // An update's `positions` replaces the full set, so lists it omits no
        // longer contain the chat.
        record.mainOrder = 0
        record.isPinnedInMain = false
        record.archiveOrder = 0
        record.folderOrders = [:]
        record.folderPinned = []
        for position in positions { applyPosition(position, to: &record) }
    }

    private static func applyPosition(_ position: ChatPosition, to record: inout Record) {
        switch position.list {
        case .chatListMain:
            record.mainOrder = position.order.rawValue
            record.isPinnedInMain = position.isPinned
        case .chatListArchive:
            record.archiveOrder = position.order.rawValue
        case .chatListFolder(let folder):
            // Order 0 removes the chat from the folder.
            if position.order.rawValue == 0 {
                record.folderOrders[folder.chatFolderId] = nil
                record.folderPinned.remove(folder.chatFolderId)
            } else {
                record.folderOrders[folder.chatFolderId] = position.order.rawValue
                if position.isPinned { record.folderPinned.insert(folder.chatFolderId) }
                else { record.folderPinned.remove(folder.chatFolderId) }
            }
        }
    }

    private static func draftText(_ draft: DraftMessage?) -> String? {
        guard let draft, case .draftMessageContentText(let content) = draft.content else { return nil }
        let text = content.text.text
        return text.isEmpty ? nil : text
    }

    // MARK: - Private: mapping (lock already held)

    private func domainChat(_ record: Record) -> NodogramDomain.Chat {
        let kind: ChatKind
        var presence: UserPresence?
        var isVerified = false
        var isBot = false
        var botActiveUsers = 0
        var isServiceAccount = false
        var memberCount = 0
        var canPost = true

        switch record.type {
        case .chatTypePrivate(let t):
            kind = .privateChat(UserID(t.userId))
            isVerified = users[t.userId]?.verificationStatus?.isVerified ?? false
            switch users[t.userId]?.type {
            case .userTypeBot(let bot):
                // A bot is software: "online" or "last seen" would be fiction.
                isBot = true
                botActiveUsers = bot.activeUserCount
            case .userTypeDeleted:
                break
            default:
                if t.userId == Self.serviceAccountId || users[t.userId]?.isSupport == true {
                    isServiceAccount = true
                } else {
                    presence = statuses[t.userId].map(Self.presence)
                }
            }
        case .chatTypeSecret(let t):
            kind = .secret
            presence = statuses[t.userId].map(Self.presence)
        case .chatTypeBasicGroup(let t):
            kind = .basicGroup
            if let group = basicGroups[t.basicGroupId] {
                memberCount = group.memberCount
                canPost = Self.canPost(status: group.status, isChannel: false)
            }
        case .chatTypeSupergroup(let t):
            kind = t.isChannel ? .channel : .supergroup
            if let group = supergroups[t.supergroupId] {
                memberCount = group.memberCount
                canPost = Self.canPost(status: group.status, isChannel: t.isChannel)
            } else if t.isChannel {
                canPost = false
            }
        }

        let avatarPath: String? = {
            if let path = record.downloadedAvatarPath { return path }
            guard let local = record.photo?.small.local,
                  local.isDownloadingCompleted, !local.path.isEmpty else { return nil }
            return local.path
        }()

        let isSaved = record.id == myUserId
        if isSaved { presence = nil }

        return NodogramDomain.Chat(
            id: ChatID(record.id),
            title: isSaved ? "Saved Messages" : (record.title.isEmpty ? "Deleted Account" : record.title),
            kind: kind,
            lastMessage: record.lastMessage.map { preview(for: $0, in: kind) },
            unreadCount: record.unreadCount,
            unreadMentionCount: record.unreadMentionCount,
            isPinned: record.isPinnedInMain,
            isMuted: record.muteFor > 0,
            hasDraft: record.draftText != nil,
            isVerified: isVerified,
            order: record.mainOrder,
            archiveOrder: record.archiveOrder,
            isMarkedAsUnread: record.isMarkedAsUnread,
            avatarPath: avatarPath,
            avatarThumbnail: record.photo?.minithumbnail?.data,
            presence: presence,
            draftText: record.draftText,
            isSavedMessages: isSaved,
            isBot: isBot,
            botActiveUsers: botActiveUsers,
            isServiceAccount: isServiceAccount || record.id == Self.serviceAccountId,
            memberCount: memberCount,
            canPost: isServiceAccount ? false : canPost,
            hasProtectedContent: record.hasProtectedContent,
            folderOrders: record.folderOrders,
            folderPinned: record.folderPinned
        )
    }

    private func preview(for message: TDLibKit.Message, in kind: ChatKind) -> MessagePreview {
        let content = ContentMapping.map(message.content)
        let sender = senderName(message.senderId, short: true)

        // Service events read as a sentence: "Ali joined the group".
        let text = content.isService
            ? [message.isOutgoing ? "You" : sender, content.text].filter { !$0.isEmpty }.joined(separator: " ")
            : content.text

        let showsSender: Bool = {
            switch kind {
            case .basicGroup, .supergroup: return !content.isService
            default: return false
            }
        }()

        return MessagePreview(
            messageID: MessageID(message.id),
            text: text,
            senderName: message.isOutgoing ? "You" : (showsSender ? sender : nil),
            date: Date(timeIntervalSince1970: TimeInterval(message.date)),
            isOutgoing: message.isOutgoing,
            hasAttachment: content.attachmentLabel != nil,
            attachmentLabel: content.attachmentLabel
        )
    }

    private func domainMessage(_ message: TDLibKit.Message) -> NodogramDomain.Message {
        let content = ContentMapping.map(message.content)

        let sendState: MessageSendState? = {
            switch message.sendingState {
            case .messageSendingStatePending: return .sending
            case .messageSendingStateFailed(let failed): return .failed(reason: failed.error.message)
            case nil: return message.isOutgoing ? .sent : nil
            }
        }()

        let lastReadOutbox = records[message.chatId]?.lastReadOutboxMessageId ?? 0
        let info = interaction(message.interactionInfo, isChannelPost: message.isChannelPost)

        var replyToID: MessageID?
        var replyPreview: ReplyPreview?
        if case .messageReplyToMessage(let reply) = message.replyTo {
            if reply.chatId == message.chatId || reply.chatId == 0 {
                replyToID = MessageID(reply.messageId)
            }
            // Content is included when the replied message lives elsewhere
            // (another chat) — then it is shown as-is.
            if let content = reply.content {
                let mapped = ContentMapping.map(content)
                replyPreview = ReplyPreview(
                    messageID: MessageID(reply.messageId),
                    senderName: reply.origin.map(originName) ?? "",
                    text: reply.quote?.text.text ?? (mapped.text.isEmpty ? (mapped.attachmentLabel ?? "") : mapped.text))
            } else if let quote = reply.quote {
                replyPreview = ReplyPreview(messageID: MessageID(reply.messageId), senderName: "", text: quote.text.text)
            }
        }

        let threadID: Int64? = {
            if case .messageTopicThread(let thread) = message.topicId { return thread.messageThreadId }
            return nil
        }()

        return NodogramDomain.Message(
            id: MessageID(message.id),
            chatID: ChatID(message.chatId),
            senderID: {
                if case .messageSenderUser(let s) = message.senderId { return UserID(s.userId) }
                return nil
            }(),
            senderName: senderName(message.senderId, short: false),
            text: content.text,
            date: Date(timeIntervalSince1970: TimeInterval(message.date)),
            editDate: message.editDate > 0
                ? Date(timeIntervalSince1970: TimeInterval(message.editDate)) : nil,
            isOutgoing: message.isOutgoing,
            sendState: sendState,
            readDate: nil,
            isReadByRecipient: message.isOutgoing && message.id <= lastReadOutbox,
            replyToMessageID: replyToID,
            attachmentLabel: content.attachmentLabel,
            isService: content.isService,
            entities: content.entities,
            media: MediaMapping.media(message.content),
            canBeSaved: message.canBeSaved,
            albumID: message.mediaAlbumId.rawValue,
            poll: {
                if case .messagePoll(let poll) = message.content { return PollMapping.map(poll) }
                return nil
            }(),
            viewCount: info.views,
            forwardCount: info.forwards,
            reactions: info.reactions,
            commentCount: info.comments,
            recentCommenters: info.commenters,
            forwardedFrom: message.forwardInfo.map {
                ForwardOrigin(name: originName($0.origin),
                              date: Date(timeIntervalSince1970: TimeInterval($0.date)))
            },
            replyPreview: replyPreview,
            isChannelPost: message.isChannelPost,
            authorSignature: message.authorSignature,
            threadID: threadID,
            isEphemeral: message.selfDestructType != nil || message.selfDestructIn > 0 || message.autoDeleteIn > 0
                || { if case .chatTypeSecret = records[message.chatId]?.type { return true }; return false }()
        )
    }

    private func senderName(_ sender: MessageSender, short: Bool) -> String {
        switch sender {
        case .messageSenderUser(let s):
            guard let user = users[s.userId] else { return "" }
            if short, !user.firstName.isEmpty { return user.firstName }
            return Self.fullName(user)
        case .messageSenderChat(let s):
            return records[s.chatId]?.title ?? ""
        }
    }

    private static func fullName(_ user: TDLibKit.User) -> String {
        [user.firstName, user.lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private struct Interaction {
        var views = 0
        var forwards = 0
        var reactions: [ReactionSummary] = []
        var comments: Int?
        var commenters: [Commenter] = []
    }

    /// `isChannelPost` decides whether a reply count is a comments section;
    /// nil (live updates) keeps whatever Telegram reports.
    private func interaction(_ info: MessageInteractionInfo?, isChannelPost: Bool?) -> Interaction {
        guard let info else { return Interaction() }
        let reactions: [ReactionSummary] = (info.reactions?.reactions ?? []).compactMap { reaction in
            let kind: ReactionSummary.Kind
            switch reaction.type {
            case .reactionTypeEmoji(let e): kind = .emoji(e.emoji)
            case .reactionTypeCustomEmoji(let c): kind = .customEmoji(c.customEmojiId.rawValue)
            case .reactionTypePaid: kind = .paid
            }
            return ReactionSummary(kind: kind, count: reaction.totalCount, isChosen: reaction.isChosen)
        }
        let comments: Int? = (isChannelPost ?? true) ? info.replyInfo.map(\.replyCount) : nil
        let commenters: [Commenter] = (info.replyInfo?.recentReplierIds ?? []).prefix(3).map { sender in
            switch sender {
            case .messageSenderUser(let u):
                return Commenter(id: u.userId, name: users[u.userId].map(Self.fullName) ?? "")
            case .messageSenderChat(let c):
                return Commenter(id: c.chatId, name: records[c.chatId]?.title ?? "")
            }
        }
        return Interaction(views: info.viewCount, forwards: info.forwardCount, reactions: reactions,
                           comments: comments, commenters: commenters)
    }

    /// Who a forward or cross-chat reply credits.
    private func originName(_ origin: MessageOrigin) -> String {
        switch origin {
        case .messageOriginUser(let o):
            return users[o.senderUserId].map(Self.fullName) ?? "Unknown"
        case .messageOriginHiddenUser(let o):
            return o.senderName
        case .messageOriginChat(let o):
            let title = records[o.senderChatId]?.title ?? "Group"
            return o.authorSignature.isEmpty ? title : "\(title) (\(o.authorSignature))"
        case .messageOriginChannel(let o):
            let title = records[o.chatId]?.title ?? "Channel"
            return o.authorSignature.isEmpty ? title : "\(title) (\(o.authorSignature))"
        }
    }

    /// Channels: only the owner and admins allowed to post. Groups: anyone who
    /// is still a member and not muted by a restriction.
    private static func canPost(status: ChatMemberStatus, isChannel: Bool) -> Bool {
        switch status {
        case .chatMemberStatusCreator: return true
        case .chatMemberStatusAdministrator(let admin): return isChannel ? admin.rights.canPostMessages : true
        case .chatMemberStatusMember: return !isChannel
        case .chatMemberStatusRestricted(let restricted): return !isChannel && restricted.permissions.canSendBasicMessages
        case .chatMemberStatusLeft, .chatMemberStatusBanned: return false
        }
    }

    /// `nil` means the action was cancelled.
    private static func activity(_ action: ChatAction) -> ChatActivity? {
        switch action {
        case .chatActionCancel: return nil
        case .chatActionTyping: return .typing
        case .chatActionRecordingVoiceNote: return .recordingVoice
        case .chatActionRecordingVideoNote, .chatActionRecordingVideo: return .recordingVideoNote
        case .chatActionUploadingPhoto: return .uploadingPhoto
        case .chatActionUploadingVideo, .chatActionUploadingVideoNote: return .uploadingVideo
        case .chatActionUploadingDocument, .chatActionUploadingVoiceNote: return .uploadingFile
        case .chatActionChoosingSticker: return .choosingSticker
        default: return .other
        }
    }

    private static func presence(_ status: UserStatus) -> UserPresence {
        switch status {
        case .userStatusOnline: return .online
        case .userStatusOffline(let s): return .lastSeen(Date(timeIntervalSince1970: TimeInterval(s.wasOnline)))
        case .userStatusRecently: return .recently
        case .userStatusLastWeek: return .withinWeek
        case .userStatusLastMonth: return .withinMonth
        case .userStatusEmpty: return .longAgo
        }
    }
}
