//  MessageArchive — keeps messages that their sender later deletes.
//
//  How it works: every message this Mac receives is recorded here. When
//  Telegram reports a permanent deletion, the record is marked deleted rather
//  than removed, and the conversation shows it in place, clearly labelled.
//
//  What it cannot do, stated so the UI never overclaims:
//    - It cannot recover a message this Mac never received — e.g. one sent
//      and deleted while Nodogram was closed and never synced.
//    - It does not undo the deletion on Telegram. The message is gone there;
//      this is a private local copy.
//
//  Message content is encrypted with AES-GCM under a Keychain-held key
//  (Documentation/SECURITY_MODEL.md §6). Only ids and dates are stored in the
//  clear, because they are needed for lookups and expiry.

import CryptoKit
import Foundation
import GRDB
import NodogramDomain

public actor MessageArchive {

    /// What is sealed per message. Kept deliberately small: text, formatting
    /// and a label for media. Media files themselves are not archived.
    struct Payload: Codable {
        var text: String
        var entities: [TextEntity]
        var attachmentLabel: String?
        var senderName: String
        var senderID: Int64?
        var isOutgoing: Bool
        var isService: Bool
        var editDate: Date?
    }

    private let database: DatabaseQueue
    private let key: SymmetricKey

    // MARK: - Opening

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var registry: [String: MessageArchive] = [:]

    /// One archive per file per process: two SQLite connections writing the
    /// same file independently invite "database is locked" errors.
    public static func shared(directory: URL, key: SymmetricKey) throws -> MessageArchive {
        let path = directory.appendingPathComponent("archive.sqlite").path
        registryLock.lock(); defer { registryLock.unlock() }
        if let existing = registry[path] { return existing }
        let archive = try MessageArchive(path: path, key: key)
        registry[path] = archive
        return archive
    }

    /// Opens (creating if needed) an archive at `path`. Tests pass their own key.
    public init(path: String, key: SymmetricKey) throws {
        var configuration = Configuration()
        configuration.label = "MessageArchive"
        self.database = try DatabaseQueue(path: path, configuration: configuration)
        self.key = key
        try Self.migrator.migrate(database)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // Append-only: a shipped migration is never edited (DATA_MODEL.md §4).
        migrator.registerMigration("v1_archive") { db in
            try db.execute(sql: """
                CREATE TABLE archived_message (
                    chat_id    INTEGER NOT NULL,
                    message_id INTEGER NOT NULL,
                    sent_at    REAL    NOT NULL,
                    stored_at  REAL    NOT NULL,
                    deleted_at REAL,
                    payload    BLOB    NOT NULL,
                    PRIMARY KEY (chat_id, message_id)
                );
                CREATE INDEX idx_archive_deleted ON archived_message(chat_id, deleted_at)
                    WHERE deleted_at IS NOT NULL;
                CREATE INDEX idx_archive_stored ON archived_message(stored_at);
                """)
        }
        migrator.registerMigration("v2_edit_history") { db in
            try db.execute(sql: """
                CREATE TABLE message_edit (
                    chat_id    INTEGER NOT NULL,
                    message_id INTEGER NOT NULL,
                    edited_at  REAL    NOT NULL,
                    payload    BLOB    NOT NULL
                );
                CREATE INDEX idx_edit_message ON message_edit(chat_id, message_id);
                """)
        }
        return migrator
    }

    // MARK: - Recording

    /// Records received messages. Pending sends (temporary ids) and messages
    /// already marked deleted are skipped; re-recording a known message keeps
    /// the first copy, so a later edit cannot overwrite what was received.
    public func record(_ messages: [Message]) {
        let rows = messages.filter { !$0.isPending && !$0.isDeleted }
        guard !rows.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        let sealed: [(Message, Data)] = rows.compactMap { message in
            seal(message).map { (message, $0) }
        }
        try? database.write { db in
            for (message, payload) in sealed {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO archived_message
                        (chat_id, message_id, sent_at, stored_at, deleted_at, payload)
                    VALUES (?, ?, ?, ?, NULL, ?)
                    """, arguments: [
                        message.chatID.rawValue, message.id.rawValue,
                        message.date.timeIntervalSince1970, now, payload,
                    ])
            }
        }
    }

    /// Drops messages entirely — used when the user deleted them themselves,
    /// which must not leave a "Deleted" copy behind.
    public func forget(chatID: ChatID, messageIDs: [MessageID]) {
        guard !messageIDs.isEmpty else { return }
        let ids = messageIDs.map(\.rawValue)
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible] = [chatID.rawValue]
        arguments.append(contentsOf: ids)
        try? database.write { db in
            try db.execute(sql: "DELETE FROM archived_message WHERE chat_id = ? AND message_id IN (\(placeholders))",
                           arguments: StatementArguments(arguments))
            try db.execute(sql: "DELETE FROM message_edit WHERE chat_id = ? AND message_id IN (\(placeholders))",
                           arguments: StatementArguments(arguments))
        }
    }

    // MARK: - Edit history

    /// Records a new version of a message's text. The original stays in
    /// `archived_message`; each edit is kept here, sealed the same way. Only
    /// messages that were recorded are tracked, and repeats are ignored.
    public func recordEdit(chatID: ChatID, messageID: MessageID, text: String, at date: Date = Date()) {
        let versions = editHistory(chatID: chatID, messageID: messageID)
        guard !versions.isEmpty, versions.last?.text != text,
              let plain = text.data(using: .utf8),
              let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        try? database.write { db in
            try db.execute(sql: """
                INSERT INTO message_edit (chat_id, message_id, edited_at, payload) VALUES (?, ?, ?, ?)
                """, arguments: [chatID.rawValue, messageID.rawValue, date.timeIntervalSince1970, sealed])
        }
    }

    public struct Version: Sendable, Hashable {
        public let date: Date
        public let text: String
    }

    /// Every known version of a message, original first. Empty when the
    /// message was never recorded.
    public func editHistory(chatID: ChatID, messageID: MessageID) -> [Version] {
        let result = try? database.read { db -> [Version] in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM archived_message WHERE chat_id = ? AND message_id = ?
                """, arguments: [chatID.rawValue, messageID.rawValue]),
                  let original = open(row) else { return [] }
            var versions = [Version(date: original.date, text: original.text)]
            let edits = try Row.fetchAll(db, sql: """
                SELECT edited_at, payload FROM message_edit WHERE chat_id = ? AND message_id = ?
                ORDER BY edited_at
                """, arguments: [chatID.rawValue, messageID.rawValue])
            for edit in edits {
                guard let sealed: Data = edit["payload"],
                      let box = try? AES.GCM.SealedBox(combined: sealed),
                      let plain = try? AES.GCM.open(box, using: key),
                      let text = String(data: plain, encoding: .utf8) else { continue }
                versions.append(Version(date: Date(timeIntervalSince1970: edit["edited_at"]), text: text))
            }
            return versions
        }
        return result ?? []
    }

    /// Marks messages deleted and returns the archived copies, ready to show
    /// in place. Messages that were never recorded are simply not returned.
    public func markDeleted(chatID: ChatID, messageIDs: [MessageID], at date: Date = Date()) -> [Message] {
        guard !messageIDs.isEmpty else { return [] }
        let ids = messageIDs.map(\.rawValue)
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let rows: [Row] = (try? database.write { db in
            var arguments: [DatabaseValueConvertible] = [date.timeIntervalSince1970, chatID.rawValue]
            arguments.append(contentsOf: ids)
            try db.execute(sql: """
                UPDATE archived_message SET deleted_at = ?
                WHERE chat_id = ? AND deleted_at IS NULL AND message_id IN (\(placeholders))
                """, arguments: StatementArguments(arguments))

            var select: [DatabaseValueConvertible] = [chatID.rawValue]
            select.append(contentsOf: ids)
            return try Row.fetchAll(db, sql: """
                SELECT * FROM archived_message
                WHERE chat_id = ? AND message_id IN (\(placeholders)) AND deleted_at IS NOT NULL
                """, arguments: StatementArguments(select))
        }) ?? []
        return rows.compactMap(open)
    }

    /// Deleted messages in a chat with ids in `range`, to merge into a page of
    /// history when a conversation is opened or scrolled.
    public func deletedMessages(in chatID: ChatID, ids range: ClosedRange<Int64>) -> [Message] {
        let rows: [Row] = (try? database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM archived_message
                WHERE chat_id = ? AND deleted_at IS NOT NULL AND message_id BETWEEN ? AND ?
                ORDER BY message_id
                """, arguments: [chatID.rawValue, range.lowerBound, range.upperBound])
        }) ?? []
        return rows.compactMap(open)
    }

    /// The most recently deleted messages across all chats, newest deletion
    /// first — the Local Archive section.
    public func recentlyDeleted(limit: Int = 200) -> [Message] {
        let rows: [Row] = (try? database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM archived_message
                WHERE deleted_at IS NOT NULL
                ORDER BY deleted_at DESC
                LIMIT ?
                """, arguments: [limit])
        }) ?? []
        return rows.compactMap(open)
    }

    // MARK: - Retention

    /// Drops ordinary (not deleted) records after `keepReceived`, and deleted
    /// ones after `keepDeleted` (nil = forever).
    public func applyRetention(keepReceived: TimeInterval, keepDeleted: TimeInterval?) {
        let now = Date().timeIntervalSince1970
        try? database.write { db in
            try db.execute(sql: "DELETE FROM archived_message WHERE deleted_at IS NULL AND stored_at < ?",
                           arguments: [now - keepReceived])
            try db.execute(sql: """
                DELETE FROM message_edit WHERE NOT EXISTS (
                    SELECT 1 FROM archived_message a
                    WHERE a.chat_id = message_edit.chat_id AND a.message_id = message_edit.message_id)
                """)
            if let keepDeleted {
                try db.execute(sql: "DELETE FROM archived_message WHERE deleted_at IS NOT NULL AND deleted_at < ?",
                               arguments: [now - keepDeleted])
            }
        }
    }

    public struct Statistics: Sendable, Equatable {
        public let received: Int
        public let deleted: Int
    }

    public func statistics() -> Statistics {
        let counts = try? database.read { db -> (Int, Int) in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM archived_message") ?? 0
            let deleted = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM archived_message WHERE deleted_at IS NOT NULL") ?? 0
            return (total - deleted, deleted)
        }
        return Statistics(received: counts?.0 ?? 0, deleted: counts?.1 ?? 0)
    }

    /// Erases everything, then compacts the file so freed pages do not keep
    /// old ciphertext around.
    public func eraseAll() {
        try? database.write { db in
            try db.execute(sql: "DELETE FROM archived_message")
            try db.execute(sql: "DELETE FROM message_edit")
        }
        try? database.vacuum()
    }

    // MARK: - Sealing

    private func seal(_ message: Message) -> Data? {
        let payload = Payload(
            text: message.text, entities: message.entities, attachmentLabel: message.attachmentLabel,
            senderName: message.senderName, senderID: message.senderID?.rawValue,
            isOutgoing: message.isOutgoing, isService: message.isService, editDate: message.editDate)
        guard let plain = try? JSONEncoder().encode(payload) else { return nil }
        return try? AES.GCM.seal(plain, using: key).combined
    }

    private func open(_ row: Row) -> Message? {
        guard
            let sealed: Data = row["payload"],
            let box = try? AES.GCM.SealedBox(combined: sealed),
            let plain = try? AES.GCM.open(box, using: key),
            let payload = try? JSONDecoder().decode(Payload.self, from: plain)
        else { return nil }

        let deleted: Double? = row["deleted_at"]
        return Message(
            id: MessageID(row["message_id"]),
            chatID: ChatID(row["chat_id"]),
            senderID: payload.senderID.map(UserID.init),
            senderName: payload.senderName,
            text: payload.text,
            date: Date(timeIntervalSince1970: row["sent_at"]),
            editDate: payload.editDate,
            isOutgoing: payload.isOutgoing,
            attachmentLabel: payload.attachmentLabel,
            isService: payload.isService,
            entities: payload.entities,
            // An archived copy is never offered for saving: it may hold media
            // labels only, and the sender chose to withdraw the original.
            canBeSaved: false,
            deletedAt: deleted.map(Date.init(timeIntervalSince1970:))
        )
    }
}
