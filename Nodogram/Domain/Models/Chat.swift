//  Chat and message domain models.
//
//  Deliberately NOT a mirror of TDLib's types. These carry only what Nodogram's
//  UI and local features need, so TDLib churn stops at the mapping layer.

import Foundation

public enum ChatKind: Hashable, Sendable {
    case privateChat(UserID)
    case basicGroup
    case supergroup
    case channel
    case secret
}

public struct Chat: Identifiable, Hashable, Sendable {
    public let id: ChatID
    public var title: String
    public var kind: ChatKind
    public var lastMessage: MessagePreview?
    public var unreadCount: Int
    public var unreadMentionCount: Int
    public var isPinned: Bool
    public var isMuted: Bool
    public var hasDraft: Bool
    public var isVerified: Bool
    /// Position in the main chat list. `0` means "not in this list" — TDLib's
    /// own convention, kept so the two can never disagree.
    public var order: Int64
    /// Position in the archive list, with the same `0` convention.
    public var archiveOrder: Int64
    public var isMarkedAsUnread: Bool
    /// Local path of the downloaded small avatar, once available.
    public var avatarPath: String?
    /// A tiny inline JPEG Telegram ships with every chat photo, usable as a
    /// placeholder before the real avatar has downloaded.
    public var avatarThumbnail: Data?
    /// Online/last-seen state, for private chats only.
    public var presence: UserPresence?
    /// Draft text, as synced through Telegram, so it survives restarts and
    /// appears on the user's other devices.
    public var draftText: String?
    /// The user's own chat with themselves, presented as "Saved Messages".
    public var isSavedMessages: Bool

    public init(
        id: ChatID,
        title: String,
        kind: ChatKind,
        lastMessage: MessagePreview? = nil,
        unreadCount: Int = 0,
        unreadMentionCount: Int = 0,
        isPinned: Bool = false,
        isMuted: Bool = false,
        hasDraft: Bool = false,
        isVerified: Bool = false,
        order: Int64 = 0,
        archiveOrder: Int64 = 0,
        isMarkedAsUnread: Bool = false,
        avatarPath: String? = nil,
        avatarThumbnail: Data? = nil,
        presence: UserPresence? = nil,
        draftText: String? = nil,
        isSavedMessages: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.hasDraft = hasDraft
        self.isVerified = isVerified
        self.order = order
        self.archiveOrder = archiveOrder
        self.isMarkedAsUnread = isMarkedAsUnread
        self.avatarPath = avatarPath
        self.avatarThumbnail = avatarThumbnail
        self.presence = presence
        self.draftText = draftText
        self.isSavedMessages = isSavedMessages
    }

    /// Unread state as the user perceives it: Telegram's count, or the explicit
    /// "mark as unread" flag that has no count attached.
    public var appearsUnread: Bool { unreadCount > 0 || isMarkedAsUnread }

    /// Group-like chats show the sender name in the list preview; private ones
    /// do not, because it would just repeat the chat title.
    public var showsSenderInPreview: Bool {
        switch kind {
        case .basicGroup, .supergroup: return true
        case .privateChat, .channel, .secret: return false
        }
    }
}

public struct MessagePreview: Hashable, Sendable {
    public let messageID: MessageID
    public let text: String
    public let senderName: String?
    public let date: Date
    public let isOutgoing: Bool
    public let hasAttachment: Bool
    /// Short label for non-text content ("Photo", "Voice message").
    public let attachmentLabel: String?

    public init(
        messageID: MessageID,
        text: String,
        senderName: String?,
        date: Date,
        isOutgoing: Bool,
        hasAttachment: Bool = false,
        attachmentLabel: String? = nil
    ) {
        self.messageID = messageID
        self.text = text
        self.senderName = senderName
        self.date = date
        self.isOutgoing = isOutgoing
        self.hasAttachment = hasAttachment
        self.attachmentLabel = attachmentLabel
    }

    /// What the chat list shows: the text, or the attachment label when a
    /// message has no text of its own.
    public var displayText: String {
        if !text.isEmpty { return text }
        return attachmentLabel ?? ""
    }
}

/// Delivery state. Server-confirmed state is kept separate from local
/// optimistic state so the two can never be conflated (brief §8).
public enum MessageSendState: Hashable, Sendable {
    case sending
    case sent
    case failed(reason: String)
    /// Queued locally because the device is offline; TDLib resends on reconnect.
    case offlinePending
}

public struct Message: Identifiable, Hashable, Sendable {
    public let id: MessageID
    public let chatID: ChatID
    public var senderID: UserID?
    public var senderName: String
    public var text: String
    public var date: Date
    public var editDate: Date?
    public var isOutgoing: Bool
    public var sendState: MessageSendState?
    public var readDate: MessageReadDate?
    /// Whether the recipient has read this outgoing message, from Telegram's
    /// read-outbox marker. Known even when the exact time is not — which is
    /// exactly why it is separate from `readDate`.
    public var isReadByRecipient: Bool
    public var replyToMessageID: MessageID?
    /// Short label for non-text content ("Photo", "Document · report.pdf").
    public var attachmentLabel: String?
    /// Formatting runs over `text` (bold, links, code…).
    public var entities: [TextEntity]
    /// Photo, video, voice and so on. `attachmentLabel` remains as a text
    /// fallback for kinds that have no richer view.
    public var media: MessageMedia?
    /// False when the chat forbids saving content. Nodogram honours this: such
    /// media can be viewed but not saved, revealed in Finder or copied.
    public var canBeSaved: Bool
    /// Messages sharing a non-zero album id were sent together.
    public var albumID: Int64
    /// Set when the sender deleted this message after this Mac received it.
    /// Such a message exists only in Nodogram's local archive, never on
    /// Telegram, and is always shown as deleted — never passed off as live.
    public var deletedAt: Date?
    /// A service event ("joined the group", "pinned a message") rather than
    /// something a person wrote. Rendered as a centred line, not a bubble, and
    /// `text` holds the action phrase without the actor's name.
    public var isService: Bool

    public init(
        id: MessageID,
        chatID: ChatID,
        senderID: UserID? = nil,
        senderName: String = "",
        text: String = "",
        date: Date,
        editDate: Date? = nil,
        isOutgoing: Bool = false,
        sendState: MessageSendState? = nil,
        readDate: MessageReadDate? = nil,
        isReadByRecipient: Bool = false,
        replyToMessageID: MessageID? = nil,
        attachmentLabel: String? = nil,
        isService: Bool = false,
        entities: [TextEntity] = [],
        media: MessageMedia? = nil,
        canBeSaved: Bool = true,
        albumID: Int64 = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.date = date
        self.editDate = editDate
        self.isOutgoing = isOutgoing
        self.sendState = sendState
        self.readDate = readDate
        self.isReadByRecipient = isReadByRecipient
        self.replyToMessageID = replyToMessageID
        self.attachmentLabel = attachmentLabel
        self.isService = isService
        self.entities = entities
        self.media = media
        self.canBeSaved = canBeSaved
        self.albumID = albumID
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// Whether this message is still waiting on the server.
    public var isPending: Bool {
        switch sendState {
        case .sending, .offlinePending: return true
        default: return false
        }
    }

    public var wasEdited: Bool { editDate != nil }
}
