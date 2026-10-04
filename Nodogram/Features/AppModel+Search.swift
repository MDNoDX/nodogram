//  Search: in the open chat (⌘F) and everywhere (⌘K), plus the content
//  sections (Media, Files, Links, Voice Messages).

import Foundation
import NodogramDomain
import NodogramTelegram

extension AppModel {

    // MARK: - In-chat search (⌘F)

    public func beginConversationSearch() {
        guard selectedChatID != nil else { return }
        conversationSearch = ConversationSearchState()
    }

    public func endConversationSearch() {
        conversationSearch = nil
    }

    public func runConversationSearch(_ query: String) {
        guard let gateway, let chatID = selectedChatID else { return }
        conversationSearch?.query = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            conversationSearch?.results = []
            return
        }
        conversationSearch?.isSearching = true
        Task { [weak self] in
            let found = (try? await gateway.search(trimmed, in: chatID))?.messages ?? []
            guard let self, self.conversationSearch?.query == query else { return }
            self.conversationSearch?.results = found
            self.conversationSearch?.index = 0
            self.conversationSearch?.isSearching = false
            if let first = found.first { self.jump(to: first.id) }
        }
    }

    /// Moves between results; results are newest first, so "next" goes older.
    public func stepConversationSearch(_ delta: Int) {
        guard var state = conversationSearch, !state.results.isEmpty else { return }
        state.index = (state.index + delta + state.results.count) % state.results.count
        conversationSearch = state
        jump(to: state.results[state.index].id)
    }

    // MARK: - Everywhere (⌘K)

    public func searchMessagesEverywhere(_ query: String) async -> [Message] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gateway, trimmed.count >= 2 else { return [] }
        return (try? await gateway.searchEverywhere(trimmed))?.messages ?? []
    }

    public func chatTitle(_ id: ChatID) -> String {
        chatsByID[id]?.title ?? gateway?.chatTitle(id) ?? "Chat"
    }

    // MARK: - Content sections

    /// Collects one kind of content across chats.
    ///
    /// Telegram's global search ignores some filters (verified: the poll
    /// filter returned photos and videos), so results are checked by kind and,
    /// when the global result is thin, supplemented by per-chat searches of the
    /// most recent chats.
    public func loadContent(_ filter: TelegramGateway.MediaFilter) async -> [Message] {
        guard let gateway else { return [] }
        let matches: (Message) -> Bool = { message in
            switch (filter, message.media) {
            case (.photosAndVideos, .photo?), (.photosAndVideos, .video?): return true
            case (.files, .document?): return true
            case (.voice, .voiceNote?): return true
            case (.music, .audio?): return true
            case (.links, _): return message.entities.contains { entity in
                switch entity.kind { case .url, .textLink: return true; default: return false } }
            default: return false
            }
        }

        var collected = ((try? await gateway.searchAll(filter, limit: 100))?.messages ?? []).filter(matches)
        if collected.count < 40 {
            let recent = chatsByID.values.filter { $0.order != 0 }.sorted { $0.order > $1.order }.prefix(30)
            for chat in recent {
                let found = ((try? await gateway.searchContent(filter, in: chat.id, limit: 15)) ?? []).filter(matches)
                collected += found
            }
        }
        var seen = Set<String>()
        return collected
            .filter { seen.insert("\($0.chatID.rawValue)-\($0.id.rawValue)").inserted }
            .sorted { $0.date > $1.date }
    }

    /// One kind of content in one chat — the chat's shared media.
    public func loadContent(_ filter: TelegramGateway.MediaFilter, in chatID: ChatID) async -> [Message] {
        guard let gateway else { return [] }
        return ((try? await gateway.searchContent(filter, in: chatID, limit: 100)) ?? [])
            .sorted { $0.date > $1.date }
    }
}
