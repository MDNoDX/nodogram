//  Account settings that live on Telegram's servers: profile, sessions,
//  privacy, notification defaults and storage.

import Foundation

public struct ProfileInfo: Hashable, Sendable {
    public var userID: UserID
    public var firstName: String
    public var lastName: String
    public var username: String
    public var phoneNumber: String
    public var bio: String
    public var isPremium: Bool

    public init(userID: UserID, firstName: String, lastName: String, username: String,
                phoneNumber: String, bio: String, isPremium: Bool) {
        self.userID = userID; self.firstName = firstName; self.lastName = lastName
        self.username = username; self.phoneNumber = phoneNumber; self.bio = bio; self.isPremium = isPremium
    }

    public var displayName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct SessionInfo: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let isCurrent: Bool
    public let applicationName: String
    public let applicationVersion: String
    public let deviceModel: String
    public let platform: String
    public let systemVersion: String
    public let location: String
    public let ipAddress: String
    public let lastActive: Date
    public let isOfficial: Bool
    /// SF Symbol for the device kind.
    public let symbol: String

    public init(id: Int64, isCurrent: Bool, applicationName: String, applicationVersion: String,
                deviceModel: String, platform: String, systemVersion: String, location: String,
                ipAddress: String, lastActive: Date, isOfficial: Bool, symbol: String) {
        self.id = id; self.isCurrent = isCurrent; self.applicationName = applicationName
        self.applicationVersion = applicationVersion; self.deviceModel = deviceModel; self.platform = platform
        self.systemVersion = systemVersion; self.location = location; self.ipAddress = ipAddress
        self.lastActive = lastActive; self.isOfficial = isOfficial; self.symbol = symbol
    }
}

/// The privacy settings Nodogram exposes, in Telegram's order.
public enum PrivacyKey: String, CaseIterable, Identifiable, Sendable {
    case phoneNumber, lastSeen, profilePhoto, bio, birthday, forwards, calls, groupInvites, voiceMessages

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .phoneNumber: return "Phone Number"
        case .lastSeen: return "Last Seen & Online"
        case .profilePhoto: return "Profile Photos"
        case .bio: return "Bio"
        case .birthday: return "Date of Birth"
        case .forwards: return "Forwarded Messages"
        case .calls: return "Calls"
        case .groupInvites: return "Invites to Groups"
        case .voiceMessages: return "Voice & Video Messages"
        }
    }

    public var symbol: String {
        switch self {
        case .phoneNumber: return "phone"
        case .lastSeen: return "clock"
        case .profilePhoto: return "person.crop.circle"
        case .bio: return "text.quote"
        case .birthday: return "gift"
        case .forwards: return "arrowshape.turn.up.right"
        case .calls: return "phone.arrow.up.right"
        case .groupInvites: return "person.2.badge.plus"
        case .voiceMessages: return "mic"
        }
    }
}

/// Who may see or do something: the base audience plus exceptions.
public struct PrivacyRule: Hashable, Sendable {
    public enum Audience: String, CaseIterable, Sendable {
        case everybody, contacts, nobody

        public var title: String {
            switch self {
            case .everybody: return "Everybody"
            case .contacts: return "My Contacts"
            case .nobody: return "Nobody"
            }
        }
    }

    public var audience: Audience
    /// Users and chats given an exception; kept so saving a new audience does
    /// not drop exceptions set on the phone.
    public var allowUserIDs: [Int64]
    public var allowChatIDs: [Int64]
    public var restrictUserIDs: [Int64]
    public var restrictChatIDs: [Int64]

    public init(audience: Audience, allowUserIDs: [Int64] = [], allowChatIDs: [Int64] = [],
                restrictUserIDs: [Int64] = [], restrictChatIDs: [Int64] = []) {
        self.audience = audience
        self.allowUserIDs = allowUserIDs; self.allowChatIDs = allowChatIDs
        self.restrictUserIDs = restrictUserIDs; self.restrictChatIDs = restrictChatIDs
    }

    public var exceptionCount: Int {
        allowUserIDs.count + allowChatIDs.count + restrictUserIDs.count + restrictChatIDs.count
    }
}

/// Default notification settings for one kind of chat.
public struct ScopeNotifications: Hashable, Sendable {
    public enum Scope: String, CaseIterable, Sendable, Identifiable {
        case privateChats, groups, channels
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .privateChats: return "Private Chats"
            case .groups: return "Groups"
            case .channels: return "Channels"
            }
        }
        public var symbol: String {
            switch self {
            case .privateChats: return "person"
            case .groups: return "person.2"
            case .channels: return "megaphone"
            }
        }
    }

    public var isMuted: Bool
    public var showPreview: Bool

    public init(isMuted: Bool, showPreview: Bool) {
        self.isMuted = isMuted; self.showPreview = showPreview
    }
}

public struct StorageUsage: Hashable, Sendable {
    public let filesSize: Int64
    public let fileCount: Int
    public let databaseSize: Int64

    public init(filesSize: Int64, fileCount: Int, databaseSize: Int64) {
        self.filesSize = filesSize; self.fileCount = fileCount; self.databaseSize = databaseSize
    }
}

// MARK: - My activity

/// A group or channel the user belongs to, with what they may do there.
public struct GroupSummary: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case owner, admin, member, left }

    public let id: ChatID
    public let title: String
    public let isChannel: Bool
    public let role: Role
    public let memberCount: Int
    public let canRemoveMembers: Bool

    public init(id: ChatID, title: String, isChannel: Bool, role: Role, memberCount: Int, canRemoveMembers: Bool) {
        self.id = id; self.title = title; self.isChannel = isChannel; self.role = role
        self.memberCount = memberCount; self.canRemoveMembers = canRemoveMembers
    }
}

public struct MemberInfo: Identifiable, Hashable, Sendable {
    public enum Role: String, Sendable { case owner, admin, member, restricted }

    public var id: UserID { userID }
    public let userID: UserID
    public let name: String
    public let username: String
    public let role: Role
    public let joinedAt: Date?
    public let isBot: Bool

    public init(userID: UserID, name: String, username: String, role: Role, joinedAt: Date?, isBot: Bool) {
        self.userID = userID; self.name = name; self.username = username
        self.role = role; self.joinedAt = joinedAt; self.isBot = isBot
    }
}

/// Someone who viewed one of the user's stories.
public struct StoryViewer: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(storyID)-\(userID)" }
    public let storyID: Int
    public let userID: Int64
    public var name: String
    public let viewedAt: Date
    public var reaction: String?
    /// When Nodogram first saw this view — Telegram keeps viewer lists only
    /// for a limited time; this copy does not expire.
    public let recordedAt: Date

    public init(storyID: Int, userID: Int64, name: String, viewedAt: Date, reaction: String?, recordedAt: Date) {
        self.storyID = storyID; self.userID = userID; self.name = name
        self.viewedAt = viewedAt; self.reaction = reaction; self.recordedAt = recordedAt
    }
}
