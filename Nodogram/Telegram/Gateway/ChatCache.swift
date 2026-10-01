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
        var lastMessage: TDLibKit.Message?
        var unreadCount: Int
        var unreadMentionCount: Int
        var lastReadOutboxMessageId: Int64
        var muteFor: Int
        var isMarkedAsUnread: Bool
        var draftText: String?
    }

    private let lock = NSLock()
    private var records: [Int64: Record] = [:]
    private var users: [Int64: TDLibKit.User] = [:]
    /// Kept apart from `users` because `updateUserStatus` arrives on its own and
    /// TDLibKit's `User` cannot be modified in place.
    private var statuses: [Int64: UserStatus] = [:]
    /// The signed-in user. Their chat with themselves is "Saved Messages".
    private var myUserId: Int64?

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
                draftText: Self.draftText(chat.draftMessage)
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
            return mutate(u.chatId) { $0.muteFor = u.notificationSettings.muteFor }

        case .updateChatDraftMessage(let u):
            return mutate(u.chatId) {
                $0.draftText = Self.draftText(u.draftMessage)
                Self.applyPositions(u.positions, to: &$0)
            }

        case .updateUser(let u):
            users[u.user.id] = u.user
            statuses[u.user.id] = u.user.status
            // In TDLib a private chat's id equals the user's id.
            return refreshPrivateChat(userId: u.user.id)

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

        case .updateChatAction(let u):
            guard case .messageSenderUser(let sender) = u.senderId else { return [] }
            return [.chatActivity(ChatID(u.chatId), user: UserID(sender.userId), activity: Self.activity(u.action))]

        case .updateMessageEdited(let u):
            return [.messageEdited(
                ChatID(u.chatId), MessageID(u.messageId),
                editDate: Date(timeIntervalSince1970: TimeInterval(u.editDate)))]

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
        for position in positions { applyPosition(position, to: &record) }
    }

    private static func applyPosition(_ position: ChatPosition, to record: inout Record) {
        switch position.list {
        case .chatListMain:
            record.mainOrder = position.order.rawValue
            record.isPinnedInMain = position.isPinned
        case .chatListArchive:
            record.archiveOrder = position.order.rawValue
        default:
            break
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

        switch record.type {
        case .chatTypePrivate(let t):
            kind = .privateChat(UserID(t.userId))
            presence = statuses[t.userId].map(Self.presence)
            isVerified = users[t.userId]?.verificationStatus?.isVerified ?? false
        case .chatTypeSecret(let t):
            kind = .secret
            presence = statuses[t.userId].map(Self.presence)
        case .chatTypeBasicGroup:
            kind = .basicGroup
        case .chatTypeSupergroup(let t):
            kind = t.isChannel ? .channel : .supergroup
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
            isSavedMessages: isSaved
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
            attachmentLabel: content.attachmentLabel,
            isService: content.isService,
            entities: content.entities,
            media: MediaMapping.media(message.content),
            canBeSaved: message.canBeSaved,
            albumID: message.mediaAlbumId.rawValue
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
