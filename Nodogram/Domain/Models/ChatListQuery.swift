//  Which chats a sidebar destination shows, and in what order.
//
//  Pure logic over domain values, so the rules that decide what the user sees
//  are unit-tested without TDLib, a network, or a window.

import Foundation

public enum ChatListFilter: Hashable, Sendable {
    case all
    case unread
    case personal
    case groups
    case channels
    case archived
    case drafts
}

public enum ChatListQuery {

    /// Filters, searches and orders chats for display.
    ///
    /// Ordering follows Telegram's own rule — descending by the list's `order`
    /// value, which already places pinned chats first — with the chat id as a
    /// tiebreaker so the order is stable when two values are equal.
    public static func visibleChats(
        _ chats: some Sequence<Chat>,
        filter: ChatListFilter,
        search: String
    ) -> [Chat] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let archived = filter == .archived

        let matching = chats.filter { chat in
            let listOrder = archived ? chat.archiveOrder : chat.order
            guard listOrder != 0 else { return false }
            guard matches(chat, filter: filter) else { return false }
            guard !query.isEmpty else { return true }
            return chat.title.lowercased().contains(query)
                || (chat.lastMessage?.displayText.lowercased().contains(query) ?? false)
        }

        return matching.sorted { lhs, rhs in
            let l = archived ? lhs.archiveOrder : lhs.order
            let r = archived ? rhs.archiveOrder : rhs.order
            if l != r { return l > r }
            return lhs.id.rawValue > rhs.id.rawValue
        }
    }

    private static func matches(_ chat: Chat, filter: ChatListFilter) -> Bool {
        switch filter {
        case .all, .archived:
            return true
        case .unread:
            return chat.appearsUnread
        case .personal:
            if case .privateChat = chat.kind { return true }
            if case .secret = chat.kind { return true }
            return false
        case .groups:
            switch chat.kind {
            case .basicGroup, .supergroup: return true
            default: return false
            }
        case .channels:
            if case .channel = chat.kind { return true }
            return false
        case .drafts:
            return !(chat.draftText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Unread total for the badge. Muted chats are excluded, matching how every
    /// Telegram client counts — a muted chat should not nag.
    public static func unreadTotal(_ chats: some Sequence<Chat>) -> Int {
        chats.reduce(0) { total, chat in
            guard chat.order != 0, !chat.isMuted else { return total }
            return total + chat.unreadCount
        }
    }
}
