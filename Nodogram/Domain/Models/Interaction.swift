//  Reactions, comments, replies, forwards and stories — the parts of a message
//  and a chat that other people interact with.

import Foundation

public struct ReactionSummary: Hashable, Sendable {
    public enum Kind: Hashable, Sendable, Codable {
        case emoji(String)
        /// A custom emoji, identified by Telegram's custom emoji id.
        case customEmoji(Int64)
        /// Telegram Stars.
        case paid
    }

    public let kind: Kind
    public let count: Int
    /// Whether the signed-in user has added this reaction.
    public let isChosen: Bool

    public init(kind: Kind, count: Int, isChosen: Bool) {
        self.kind = kind
        self.count = count
        self.isChosen = isChosen
    }
}

/// A quoted message shown above a reply.
public struct ReplyPreview: Hashable, Sendable {
    public let messageID: MessageID
    public let senderName: String
    public let text: String

    public init(messageID: MessageID, senderName: String, text: String) {
        self.messageID = messageID
        self.senderName = senderName
        self.text = text
    }
}

/// What a forwarded message credits as its origin.
public struct ForwardOrigin: Hashable, Sendable {
    public let name: String
    public let date: Date?

    public init(name: String, date: Date?) {
        self.name = name
        self.date = date
    }
}

/// Forwarding choices, matching Telegram's own: credit the original sender or
/// send as if it were your own message, with or without media captions.
public struct ForwardOptions: Hashable, Sendable {
    public var showSender: Bool
    public var showCaptions: Bool

    public init(showSender: Bool = true, showCaptions: Bool = true) {
        self.showSender = showSender
        self.showCaptions = showCaptions
    }
}

// MARK: - Stories

/// A chat (usually a person or channel) that currently has stories.
public struct StoryOwner: Hashable, Sendable, Identifiable {
    public let chatID: ChatID
    public let storyIDs: [Int]
    public let maxReadStoryID: Int
    /// Telegram's ordering value; higher first.
    public let order: Int64

    public var id: ChatID { chatID }
    public var hasUnread: Bool { storyIDs.contains { $0 > maxReadStoryID } }

    public init(chatID: ChatID, storyIDs: [Int], maxReadStoryID: Int, order: Int64) {
        self.chatID = chatID
        self.storyIDs = storyIDs
        self.maxReadStoryID = maxReadStoryID
        self.order = order
    }
}

public struct StoryItem: Hashable, Sendable, Identifiable {
    public enum Content: Hashable, Sendable {
        case photo(PhotoMedia)
        case video(VideoMedia)
        case unsupported
    }

    public let id: Int
    public let chatID: ChatID
    public let date: Date
    public let caption: String
    public let entities: [TextEntity]
    public let content: Content

    public init(id: Int, chatID: ChatID, date: Date, caption: String, entities: [TextEntity], content: Content) {
        self.id = id
        self.chatID = chatID
        self.date = date
        self.caption = caption
        self.entities = entities
        self.content = content
    }
}
