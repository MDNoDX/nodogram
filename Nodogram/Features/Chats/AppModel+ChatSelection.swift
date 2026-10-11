//  Selecting several chats at once to delete, clear, or wipe your own
//  messages from them — the chat-list equivalent of message selection.

import Foundation
import NodogramDomain

extension AppModel {

    public func beginChatSelection(with chat: ChatID) {
        isSelectingChats = true
        selectedChatIDs = [chat]
    }

    public func toggleChatSelection(_ chat: ChatID) {
        if selectedChatIDs.contains(chat) { selectedChatIDs.remove(chat) } else { selectedChatIDs.insert(chat) }
        if selectedChatIDs.isEmpty { isSelectingChats = false }
    }

    public func endChatSelection() {
        isSelectingChats = false
        selectedChatIDs = []
    }

    /// Clears history of every selected chat (for both sides where allowed).
    public func clearSelectedHistory(forEveryone: Bool) {
        let chats = Array(selectedChatIDs)
        endChatSelection()
        for chat in chats { clearHistory(chat, forEveryone: forEveryone) }
    }

    /// Deletes/leaves every selected chat.
    public func deleteSelectedChats(forEveryone: Bool) {
        let chats = Array(selectedChatIDs)
        endChatSelection()
        for chat in chats { deleteChat(chat, forEveryone: forEveryone) }
    }

    /// Wipes your own messages from every selected chat, in turn, with a live
    /// count. Reports the total removed.
    public func wipeMyMessages(from chats: [ChatID]) {
        guard !chats.isEmpty else { return }
        wipeProgress = WipeProgress(done: 0, total: chats.count, chatTitle: "")
        Task { [weak self] in
            guard let self else { return }
            var totalDeleted = 0
            for (index, chat) in chats.enumerated() {
                self.wipeProgress = WipeProgress(done: index, total: chats.count, chatTitle: self.chatTitle(chat))
                _ = await self.deleteAllMyMessages(in: chat) { done, _ in
                    self.wipeProgress = WipeProgress(done: index, total: chats.count,
                                                     chatTitle: "\(self.chatTitle(chat)) · \(done)")
                }
                totalDeleted += 1
            }
            self.wipeProgress = nil
            self.showToast("Cleared your messages from \(chats.count) chats")
        }
    }

    public func wipeMyMessagesFromSelected() {
        let chats = Array(selectedChatIDs)
        endChatSelection()
        wipeMyMessages(from: chats)
    }
}

public struct WipeProgress: Equatable, Sendable {
    public let done: Int
    public let total: Int
    public let chatTitle: String
}
