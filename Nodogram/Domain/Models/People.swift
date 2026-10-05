//  What Nodogram can show about a person: their profile as Telegram shares
//  it, plus what this Mac has observed (name and username changes).

import Foundation

public struct PersonProfile: Hashable, Sendable {
    public let userID: UserID
    public let firstName: String
    public let lastName: String
    public let usernames: [String]
    /// Usernames they turned off but still own.
    public let disabledUsernames: [String]
    /// Usernames bought on Fragment.
    public let collectibleUsernames: [String]
    public let phoneNumber: String
    public let bio: String
    public let birthday: String?
    public let isContact: Bool
    /// They have the user in their contacts too.
    public let isMutualContact: Bool
    public let isBlocked: Bool
    public let isBot: Bool
    public let isPremium: Bool
    public let isVerified: Bool
    /// Telegram flags accounts using unofficial apps (2026).
    public let usesUnofficialApp: Bool
    public let groupsInCommonCount: Int
    public let personalChannelID: ChatID?
    public let note: String

    public init(userID: UserID, firstName: String, lastName: String, usernames: [String], disabledUsernames: [String],
                collectibleUsernames: [String], phoneNumber: String, bio: String, birthday: String?, isContact: Bool,
                isMutualContact: Bool, isBlocked: Bool, isBot: Bool, isPremium: Bool, isVerified: Bool,
                usesUnofficialApp: Bool, groupsInCommonCount: Int, personalChannelID: ChatID?, note: String) {
        self.userID = userID; self.firstName = firstName; self.lastName = lastName; self.usernames = usernames
        self.disabledUsernames = disabledUsernames; self.collectibleUsernames = collectibleUsernames
        self.phoneNumber = phoneNumber; self.bio = bio; self.birthday = birthday; self.isContact = isContact
        self.isMutualContact = isMutualContact; self.isBlocked = isBlocked; self.isBot = isBot; self.isPremium = isPremium
        self.isVerified = isVerified; self.usesUnofficialApp = usesUnofficialApp
        self.groupsInCommonCount = groupsInCommonCount; self.personalChannelID = personalChannelID; self.note = note
    }

    public var displayName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// A person's name and usernames at one moment, as this Mac saw them.
public struct UserIdentity: Codable, Hashable, Sendable {
    public let name: String
    public let usernames: [String]
    public let seenAt: Date

    public init(name: String, usernames: [String], seenAt: Date) {
        self.name = name; self.usernames = usernames; self.seenAt = seenAt
    }

    public func sameAs(_ other: UserIdentity) -> Bool { name == other.name && usernames == other.usernames }
}
