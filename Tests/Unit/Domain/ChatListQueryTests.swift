import Testing
import Foundation
@testable import NodogramDomain

@Suite("ChatListQuery")
struct ChatListQueryTests {
    private func chat(_ id: Int64, _ title: String, kind: ChatKind = .basicGroup,
                      order: Int64 = 1, unread: Int = 0, muted: Bool = false, draft: String? = nil) -> Chat {
        Chat(id: ChatID(id), title: title, kind: kind, unreadCount: unread, isMuted: muted,
             hasDraft: draft != nil, order: order, draftText: draft)
    }

    @Test("Sorted by Telegram's order, highest first")
    func ordering() {
        let result = ChatListQuery.visibleChats([chat(1, "A", order: 5), chat(2, "B", order: 50), chat(3, "C", order: 20)],
                                                filter: .all, search: "")
        #expect(result.map(\.title) == ["B", "C", "A"])
    }

    @Test("Equal orders are broken by id, so the list never reshuffles")
    func stableTiebreak() {
        let result = ChatListQuery.visibleChats([chat(1, "A", order: 7), chat(2, "B", order: 7)], filter: .all, search: "")
        #expect(result.map(\.title) == ["B", "A"])
    }

    @Test("Filters by kind")
    func kindFilters() {
        let all = [chat(1, "Person", kind: .privateChat(UserID(1))), chat(2, "Team", kind: .supergroup), chat(3, "News", kind: .channel)]
        #expect(ChatListQuery.visibleChats(all, filter: .personal, search: "").map(\.title) == ["Person"])
        #expect(ChatListQuery.visibleChats(all, filter: .groups, search: "").map(\.title) == ["Team"])
        #expect(ChatListQuery.visibleChats(all, filter: .channels, search: "").map(\.title) == ["News"])
    }

    @Test("Search matches title case-insensitively")
    func search() {
        let result = ChatListQuery.visibleChats([chat(1, "Backend Team"), chat(2, "Family")], filter: .all, search: "  back ")
        #expect(result.map(\.title) == ["Backend Team"])
    }

    @Test("Drafts filter shows only chats with real draft text")
    func drafts() {
        let result = ChatListQuery.visibleChats([chat(1, "A", draft: "hi"), chat(2, "B", draft: "   "), chat(3, "C")],
                                                filter: .drafts, search: "")
        #expect(result.map(\.title) == ["A"])
    }

    @Test("Unread total ignores muted chats and chats outside the list")
    func unreadTotal() {
        let total = ChatListQuery.unreadTotal([chat(1, "A", unread: 3), chat(2, "B", unread: 10, muted: true), chat(3, "C", order: 0, unread: 4)])
        #expect(total == 3)
    }
}
