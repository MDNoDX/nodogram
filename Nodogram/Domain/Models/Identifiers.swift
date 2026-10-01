//  Strongly-typed identifiers.
//
//  Telegram ids are plain integers, which makes them trivially easy to mix up —
//  passing a chat id where a message id belongs compiles fine and fails at
//  runtime. Wrapping them makes that a compile error instead.

import Foundation

/// A local Nodogram account identifier. Local, not Telegram's user id.
public struct AccountID: Hashable, Sendable, Codable {
    public let rawValue: UUID
    public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Telegram chat identifier (`int53`).
public struct ChatID: Hashable, Sendable, Codable {
    public let rawValue: Int64
    public init(_ rawValue: Int64) { self.rawValue = rawValue }
}

/// Telegram message identifier (`int53`), unique within a chat — not globally.
public struct MessageID: Hashable, Sendable, Codable {
    public let rawValue: Int64
    public init(_ rawValue: Int64) { self.rawValue = rawValue }
}

/// Telegram user identifier (`int53`).
public struct UserID: Hashable, Sendable, Codable {
    public let rawValue: Int64
    public init(_ rawValue: Int64) { self.rawValue = rawValue }
}

extension ChatID: CustomStringConvertible {
    public var description: String { String(rawValue) }
}

extension MessageID: CustomStringConvertible {
    public var description: String { String(rawValue) }
}
