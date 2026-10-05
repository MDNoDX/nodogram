//  Merging what Nodogram Vault kept into the archive, so deletions and edits
//  the Business bot caught — including while this Mac was off — show in the
//  chat with that person and under Deleted, with their photos and voice.

import Foundation
import NodogramCore
import NodogramDomain

extension AppModel {

    /// Telegram's Bot API numbers messages 1, 2, 3…; TDLib shifts the same
    /// server ids left by 20 bits.
    nonisolated static func tdlibMessageID(fromBotID id: Int64) -> MessageID { MessageID(id << 20) }

    func startVaultSync() {
        guard vaultTask == nil, VaultClient.fromEnvironment() != nil else { return }
        vaultTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncVault()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    public func syncVault() async {
        guard keepsDeletedMessages, let client = VaultClient.fromEnvironment() else { return }
        if archive == nil, let archiveDirectory { openArchive(in: archiveDirectory) }
        guard let archive else { return }

        if let status = try? await client.status() {
            vaultStatus = VaultStatus(connected: status.connections > 0, kept: status.stats.total,
                                      deleted: status.stats.deleted, edited: status.stats.edited)
        } else {
            vaultStatus = nil
            return
        }

        let defaults = UserDefaults.standard
        let deletedSince = defaults.object(forKey: "vault.syncedDeleted") as? Date
        let editedSince = defaults.object(forKey: "vault.syncedEdited") as? Date
        var touchedChats = Set<ChatID>()

        if let items = try? await client.deleted(since: deletedSince), !items.isEmpty {
            let imported = items.map(Self.imported)
            let fresh = await archive.importMessages(imported)
            touchedChats.formUnion(imported.map(\.chatID))
            if let newest = items.compactMap(\.deletedAt).max() { defaults.set(newest, forKey: "vault.syncedDeleted") }
            // The bot already notified the phone; here, count them as new.
            if fresh > 0, selectedDestination != .localArchive { unseenDeletedCount += fresh }
        }

        if let items = try? await client.edited(since: editedSince), !items.isEmpty {
            for item in items {
                let message = Self.imported(item)
                await archive.importMessages([message])
                if let versions = try? await client.versions(chatID: item.chatId, messageID: item.messageId) {
                    await archive.importVersions(chatID: message.chatID, messageID: message.messageID,
                                                 versions: versions.map { MessageArchive.Version(date: $0.at, text: $0.text) })
                }
            }
            if let newest = items.compactMap(\.editedAt).max() { defaults.set(newest, forKey: "vault.syncedEdited") }
        }

        if let chatID = selectedChatID, touchedChats.contains(chatID), !messages.isEmpty, !hasNewerHistory {
            messages = await mergingDeleted(into: messages, chatID: chatID, openEnded: true)
        }
    }

    private static func imported(_ item: VaultClient.Item) -> MessageArchive.Imported {
        MessageArchive.Imported(
            chatID: ChatID(item.chatId), messageID: tdlibMessageID(fromBotID: item.messageId),
            senderID: item.senderId, senderName: item.senderName, text: item.text, sentAt: item.sentAt,
            deletedAt: item.deletedAt, isOutgoing: item.isOutgoing, mediaKind: item.mediaKind, mediaPath: item.localPath)
    }
}

public struct VaultStatus: Equatable, Sendable {
    public let connected: Bool
    public let kept: Int
    public let deleted: Int
    public let edited: Int
}
