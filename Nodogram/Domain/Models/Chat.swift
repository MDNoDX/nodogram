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
    public var order: Int64

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
        order: Int64 = 0
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
    }

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

    public init(
        messageID: MessageID,
        text: String,
        senderName: String?,
        date: Date,
        isOutgoing: Bool,
        hasAttachment: Bool = false
    ) {
        self.messageID = messageID
        self.text = text
        self.senderName = senderName
        self.date = date
        self.isOutgoing = isOutgoing
        self.hasAttachment = hasAttachment
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
    public var replyToMessageID: MessageID?

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
        replyToMessageID: MessageID? = nil
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
        self.replyToMessageID = replyToMessageID
    }

    public var wasEdited: Bool { editDate != nil }
}
