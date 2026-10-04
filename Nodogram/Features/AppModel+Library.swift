//  Local library: starred messages and the Local Archive list.
//
//  Stars are Nodogram's own: they live on this Mac only and never touch
//  Telegram. Saved Messages remains the way to keep something on every device.

import Foundation
import NodogramDomain

public struct StarredMessage: Codable, Hashable, Identifiable, Sendable {
    public let chatID: Int64
    public let messageID: Int64
    public let chatTitle: String
    public let senderName: String
    public let text: String
    public let attachmentLabel: String?
    public let date: Date
    public let starredAt: Date

    public var id: String { "\(chatID)-\(messageID)" }

    private static let key = "library.starred"

    static func loadAll() -> [StarredMessage] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StarredMessage].self, from: data)) ?? []
    }

    static func saveAll(_ items: [StarredMessage]) {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension AppModel {

    public func isStarred(_ message: Message) -> Bool {
        starred.contains { $0.chatID == message.chatID.rawValue && $0.messageID == message.id.rawValue }
    }

    public func toggleStar(_ message: Message) {
        if isStarred(message) {
            starred.removeAll { $0.chatID == message.chatID.rawValue && $0.messageID == message.id.rawValue }
            showToast("Removed from Starred")
        } else {
            starred.insert(StarredMessage(
                chatID: message.chatID.rawValue, messageID: message.id.rawValue,
                chatTitle: chatTitle(message.chatID),
                senderName: message.isOutgoing ? "You" : message.senderName,
                text: message.text, attachmentLabel: message.attachmentLabel,
                date: message.date, starredAt: Date()), at: 0)
            showToast("Starred")
        }
        StarredMessage.saveAll(starred)
    }

    public func unstar(_ item: StarredMessage) {
        starred.removeAll { $0.id == item.id }
        StarredMessage.saveAll(starred)
    }

    /// Messages deleted by their senders that this Mac kept, newest first.
    public func locallyArchivedMessages() async -> [Message] {
        guard keepsDeletedMessages else { return [] }
        if archive == nil, let archiveDirectory { openArchive(in: archiveDirectory) }
        guard let archive else { return [] }
        return await archive.recentlyDeleted(limit: 300)
    }
}
