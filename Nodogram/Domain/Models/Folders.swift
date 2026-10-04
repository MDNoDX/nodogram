//  Telegram chat folders.
//
//  Folders are Telegram's own (they sync with the user's phone); Nodogram
//  shows and edits them through TDLib rather than inventing a parallel system.

import Foundation

/// A folder as it appears in the sidebar.
public struct ChatFolderSummary: Identifiable, Hashable, Sendable {
    public let id: Int
    public var title: String
    /// Telegram's icon name ("Work", "Love", "Custom"…), empty when unset.
    public var iconName: String
    /// Telegram's folder colour, -1 when none.
    public var colorID: Int

    public init(id: Int, title: String, iconName: String, colorID: Int) {
        self.id = id; self.title = title; self.iconName = iconName; self.colorID = colorID
    }
}

/// Everything that defines a folder, for the editor.
public struct ChatFolderDraft: Hashable, Sendable {
    public var title: String
    public var iconName: String
    public var colorID: Int
    public var includeContacts: Bool
    public var includeNonContacts: Bool
    public var includeGroups: Bool
    public var includeChannels: Bool
    public var includeBots: Bool
    public var excludeMuted: Bool
    public var excludeRead: Bool
    public var excludeArchived: Bool
    public var includedChatIDs: [ChatID]
    public var excludedChatIDs: [ChatID]
    public var pinnedChatIDs: [ChatID]

    public init(title: String = "", iconName: String = "", colorID: Int = -1,
                includeContacts: Bool = false, includeNonContacts: Bool = false,
                includeGroups: Bool = false, includeChannels: Bool = false, includeBots: Bool = false,
                excludeMuted: Bool = false, excludeRead: Bool = false, excludeArchived: Bool = true,
                includedChatIDs: [ChatID] = [], excludedChatIDs: [ChatID] = [], pinnedChatIDs: [ChatID] = []) {
        self.title = title; self.iconName = iconName; self.colorID = colorID
        self.includeContacts = includeContacts; self.includeNonContacts = includeNonContacts
        self.includeGroups = includeGroups; self.includeChannels = includeChannels; self.includeBots = includeBots
        self.excludeMuted = excludeMuted; self.excludeRead = excludeRead; self.excludeArchived = excludeArchived
        self.includedChatIDs = includedChatIDs; self.excludedChatIDs = excludedChatIDs
        self.pinnedChatIDs = pinnedChatIDs
    }

    /// Telegram rejects a folder that includes nothing.
    public var includesAnything: Bool {
        includeContacts || includeNonContacts || includeGroups || includeChannels || includeBots
            || !includedChatIDs.isEmpty || !pinnedChatIDs.isEmpty
    }
}

/// A folder Telegram suggests, with its one-line description.
public struct RecommendedFolder: Hashable, Sendable, Identifiable {
    public var id: String { draft.title }
    public let draft: ChatFolderDraft
    public let description: String

    public init(draft: ChatFolderDraft, description: String) {
        self.draft = draft; self.description = description
    }
}

/// Telegram folder icon names, mapped to SF Symbols.
public enum FolderIcon {
    public static let all: [(name: String, symbol: String)] = [
        ("Custom", "folder"), ("All", "bubble.left.and.bubble.right"), ("Unread", "message.badge"),
        ("Unmuted", "bell"), ("Private", "person"), ("Groups", "person.2"), ("Channels", "megaphone"),
        ("Bots", "cpu"), ("Work", "briefcase"), ("Home", "house"), ("Love", "heart"),
        ("Favorite", "star"), ("Study", "graduationcap"), ("Book", "book"), ("Trade", "chart.line.uptrend.xyaxis"),
        ("Money", "dollarsign.circle"), ("Travel", "suitcase"), ("Airplane", "airplane"), ("Sport", "figure.run"),
        ("Game", "gamecontroller"), ("Party", "party.popper"), ("Flower", "camera.macro"), ("Cat", "cat"),
        ("Crown", "crown"), ("Mask", "theatermasks"), ("Light", "lightbulb"), ("Like", "hand.thumbsup"),
        ("Note", "music.note"), ("Palette", "paintpalette"), ("Setup", "gearshape"),
    ]

    public static func symbol(for name: String) -> String {
        all.first { $0.name == name }?.symbol ?? "folder"
    }
}
