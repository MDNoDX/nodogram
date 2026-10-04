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

/// Someone who recently commented on a channel post (avatars on the comments bar).
public struct Commenter: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let avatarPath: String?

    public init(id: Int64, name: String, avatarPath: String? = nil) {
        self.id = id
        self.name = name
        self.avatarPath = avatarPath
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

// MARK: - Notifications

/// A notification TDLib decided should be shown — it has already applied the
/// user's mute settings, mention rules and per-chat exceptions.
public struct ChatNotification: Hashable, Sendable, Identifiable {
    public let id: Int
    public let groupID: Int
    public let chatID: ChatID
    public let message: Message
    public let isSilent: Bool

    public init(id: Int, groupID: Int, chatID: ChatID, message: Message, isSilent: Bool) {
        self.id = id
        self.groupID = groupID
        self.chatID = chatID
        self.message = message
        self.isSilent = isSilent
    }
}

// MARK: - Sponsored messages

/// An official Telegram sponsored message. Telegram's API terms require clients
/// that show channel content to display these (clause 3.3).
public struct SponsoredItem: Hashable, Sendable, Identifiable {
    public let id: MessageID
    public let title: String
    public let text: String
    public let entities: [TextEntity]
    public let buttonText: String
    public let url: String
    public let sponsorInfo: String
    public let additionalInfo: String
    public let isRecommended: Bool
    public let media: MessageMedia?

    public init(id: MessageID, title: String, text: String, entities: [TextEntity], buttonText: String,
                url: String, sponsorInfo: String, additionalInfo: String, isRecommended: Bool,
                media: MessageMedia?) {
        self.id = id; self.title = title; self.text = text; self.entities = entities
        self.buttonText = buttonText; self.url = url; self.sponsorInfo = sponsorInfo
        self.additionalInfo = additionalInfo; self.isRecommended = isRecommended; self.media = media
    }
}

/// What to send: a file picked, pasted or dropped onto the composer.
public struct OutgoingFile: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case photo, video, document }
    public let path: String
    public let kind: Kind
    public let width: Int
    public let height: Int
    public let duration: Int

    public init(path: String, kind: Kind, width: Int = 0, height: Int = 0, duration: Int = 0) {
        self.path = path; self.kind = kind; self.width = width; self.height = height; self.duration = duration
    }
}
