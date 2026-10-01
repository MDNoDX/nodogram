//  Read-state vocabulary.
//
//  The product brief is explicit: "Do NOT invent read timestamps when the
//  protocol does not provide them." Telegram gives exactly five outcomes, and
//  this type mirrors them 1:1 so the impossible states cannot be represented.
//
//  A timestamp exists ONLY in the `.read` case. There is no `Date?` field that
//  could be quietly filled in with a guess — the type makes that unwritable.
//
//  See Documentation/ARCHITECTURE.md §6.2.

import Foundation

/// When a message was read, as far as Telegram is willing to say.
public enum MessageReadDate: Hashable, Sendable {
    /// The server confirmed a precise read time.
    case read(Date)

    /// The recipient has not read it yet.
    case unread

    /// It was read, but the server no longer retains when.
    case tooOld

    /// It was read, but the recipient hides their read times.
    case recipientPrivacyRestricted

    /// It was read, but *we* hide our read times, so Telegram reciprocally
    /// withholds theirs. This is the user's own setting, and the UI should say
    /// so rather than looking like an error.
    case ownPrivacyRestricted

    /// Whether the message is known to have been read, regardless of whether a
    /// time is available.
    public var isRead: Bool {
        switch self {
        case .read, .tooOld, .recipientPrivacyRestricted, .ownPrivacyRestricted:
            return true
        case .unread:
            return false
        }
    }

    /// The precise time, when one genuinely exists. `nil` in every other case —
    /// deliberately, so callers must handle the absence.
    public var preciseDate: Date? {
        if case .read(let date) = self { return date }
        return nil
    }

    /// Whether the absence of a time is explained by a privacy setting, which
    /// the UI presents differently from "the server forgot".
    public var isPrivacyWithheld: Bool {
        switch self {
        case .recipientPrivacyRestricted, .ownPrivacyRestricted: return true
        case .read, .unread, .tooOld: return false
        }
    }
}

/// One participant's view of a message, for "Read by" in group chats.
public struct MessageViewer: Hashable, Sendable {
    public let userID: UserID
    public let viewDate: Date

    public init(userID: UserID, viewDate: Date) {
        self.userID = userID
        self.viewDate = viewDate
    }
}
