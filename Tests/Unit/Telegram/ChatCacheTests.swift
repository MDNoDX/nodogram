//  The chat cache decides what the chat list shows. Each test feeds it the same
//  raw JSON TDLib would send and checks the domain result.

import Testing
import Foundation
import TDLibKit
@testable import NodogramTelegram
import NodogramDomain

@Suite("ChatCache")
struct ChatCacheTests {

    private func chats(_ events: [TelegramEvent]) -> [NodogramDomain.Chat] {
        events.compactMap { if case .chatUpdated(let chat) = $0 { return chat } else { return nil } }
    }

    @Test("A new chat in the main list becomes a visible domain chat")
    func newChatAppears() throws {
        let cache = ChatCache()
        let events = cache.apply(try Fixture.update(Fixture.newChat(
            id: 100, title: "Backend", positions: [Fixture.position(order: 500)], unread: 3)))

        let chat = try #require(chats(events).first)
        #expect(chat.id == ChatID(100))
        #expect(chat.title == "Backend")
        #expect(chat.order == 500)
        #expect(chat.unreadCount == 3)
        #expect(ChatListQuery.visibleChats([chat], filter: .all, search: "").count == 1)
    }

    @Test("A chat with no main-list position is not shown")
    func chatWithoutPositionIsHidden() throws {
        // TDLib sends some chats before their positions arrive; until then they
        // belong to no list and must not appear in one.
        let cache = ChatCache()
        let chat = try #require(chats(cache.apply(try Fixture.update(Fixture.newChat(id: 1, title: "X")))).first)
        #expect(chat.order == 0)
        #expect(ChatListQuery.visibleChats([chat], filter: .all, search: "").isEmpty)
    }

    @Test("A position update moves the chat, and order 0 removes it from the list")
    func positionUpdates() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.newChat(id: 1, title: "X", positions: [Fixture.position(order: 10)])))

        let moved = chats(cache.apply(try Fixture.update(
            #"{"@type":"updateChatPosition","chat_id":1,"position":\#(Fixture.position(order: 99, pinned: true))}"#)))
        #expect(moved.first?.order == 99)
        #expect(moved.first?.isPinned == true)

        let removed = chats(cache.apply(try Fixture.update(
            #"{"@type":"updateChatPosition","chat_id":1,"position":\#(Fixture.position(order: 0))}"#)))
        #expect(removed.first?.order == 0)
    }

    @Test("Archived chats carry an archive order, not a main-list order")
    func archivePosition() throws {
        let cache = ChatCache()
        let chat = try #require(chats(cache.apply(try Fixture.update(Fixture.newChat(
            id: 5, title: "Old", positions: [Fixture.position(list: "chatListArchive", order: 42)])))).first)
        #expect(chat.order == 0)
        #expect(chat.archiveOrder == 42)
        #expect(ChatListQuery.visibleChats([chat], filter: .archived, search: "").count == 1)
        #expect(ChatListQuery.visibleChats([chat], filter: .all, search: "").isEmpty)
    }

    @Test("Updates for an unknown chat are ignored rather than guessed at")
    func unknownChatIgnored() throws {
        let cache = ChatCache()
        let events = cache.apply(try Fixture.update(#"{"@type":"updateChatTitle","chat_id":404,"title":"?"}"#))
        #expect(events.isEmpty)
    }

    @Test("Reading the inbox updates the unread count")
    func readInbox() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.newChat(id: 1, title: "X", positions: [Fixture.position(order: 1)], unread: 9)))
        let updated = chats(cache.apply(try Fixture.update(
            #"{"@type":"updateChatReadInbox","chat_id":1,"last_read_inbox_message_id":500,"unread_count":0}"#)))
        #expect(updated.first?.unreadCount == 0)
    }

    @Test("Outgoing messages up to the read-outbox marker are marked read")
    func readOutboxMarksMessages() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.newChat(
            id: 1, title: "X", positions: [Fixture.position(order: 1)], lastReadOutbox: 200)))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let read = try decoder.decode(TDLibKit.Message.self, from: Data(Fixture.message(id: 150, chatId: 1, outgoing: true, content: Fixture.text("a")).utf8))
        let unread = try decoder.decode(TDLibKit.Message.self, from: Data(Fixture.message(id: 250, chatId: 1, outgoing: true, content: Fixture.text("b")).utf8))

        #expect(cache.mapMessage(read).isReadByRecipient)
        #expect(!cache.mapMessage(unread).isReadByRecipient)
        // Known to be read, but no time invented for it.
        #expect(cache.mapMessage(read).readDate == nil)
    }

    @Test("A user update names the private chat and sets presence")
    func userNamesPrivateChat() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.newChat(
            id: 7, title: "", type: Fixture.chatType("private", id: 7), positions: [Fixture.position(order: 1)])))
        let events = cache.apply(try Fixture.update(Fixture.user(
            id: 7, first: "Ali", last: "Valiyev", status: #"{"@type":"userStatusOnline","expires":2000000000}"#)))

        let chat = try #require(chats(events).first)
        #expect(chat.title == "Ali Valiyev")
        #expect(chat.presence == .online)
    }

    @Test("Group previews show the sender's first name")
    func groupPreviewSender() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.user(id: 7, first: "Ali", last: "Valiyev")))
        let chat = try #require(chats(cache.apply(try Fixture.update(Fixture.newChat(
            id: 9, title: "Team", type: Fixture.chatType("group", id: 9),
            positions: [Fixture.position(order: 1)],
            lastMessage: Fixture.message(id: 1, chatId: 9, senderUserId: 7, content: Fixture.text("Deploy is green")))))).first)

        #expect(chat.lastMessage?.senderName == "Ali")
        #expect(chat.lastMessage?.displayText == "Deploy is green")
    }

    @Test("Service events read as a sentence in the preview")
    func servicePreview() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.user(id: 7, first: "Ali")))
        let chat = try #require(chats(cache.apply(try Fixture.update(Fixture.newChat(
            id: 9, title: "Team", type: Fixture.chatType("group", id: 9),
            positions: [Fixture.position(order: 1)],
            lastMessage: Fixture.message(id: 1, chatId: 9, senderUserId: 7,
                content: #"{"@type":"messageChatJoinByLink"}"#))))).first)

        #expect(chat.lastMessage?.displayText == "Ali joined via invite link")
        #expect(chat.lastMessage?.senderName == nil)
    }

    @Test("Draft text flows through to the chat")
    func draftText() throws {
        let cache = ChatCache()
        _ = cache.apply(try Fixture.update(Fixture.newChat(id: 1, title: "X", positions: [Fixture.position(order: 1)])))
        let json = #"""
        {"@type":"updateChatDraftMessage","chat_id":1,"positions":[\#(Fixture.position(order: 1))],
         "draft_message":{"@type":"draftMessage","date":1,"effect_id":"0",
           "content":{"@type":"draftMessageContentText","text":{"@type":"formattedText","text":"half-written","entities":[]}}}}
        """#
        let chat = try #require(chats(cache.apply(try Fixture.update(json))).first)
        #expect(chat.draftText == "half-written")
        #expect(chat.hasDraft)
    }

    @Test("Cache evictions are not reported as deletions")
    func evictionIsNotDeletion() throws {
        let cache = ChatCache()
        let evicted = cache.apply(try Fixture.update(
            #"{"@type":"updateDeleteMessages","chat_id":1,"message_ids":[5],"is_permanent":false,"from_cache":true}"#))
        #expect(evicted.isEmpty)

        let deleted = cache.apply(try Fixture.update(
            #"{"@type":"updateDeleteMessages","chat_id":1,"message_ids":[5],"is_permanent":true,"from_cache":false}"#))
        guard case .messagesDeleted(let chatID, let ids) = deleted.first else {
            Issue.record("expected messagesDeleted, got \(deleted)")
            return
        }
        #expect(chatID == ChatID(1))
        #expect(ids == [MessageID(5)])
    }
}

@Suite("ContentMapping")
struct ContentMappingTests {
    private func content(_ json: String) throws -> MessageContent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MessageContent.self, from: Data(json.utf8))
    }

    @Test("Text is text, with no attachment label")
    func text() throws {
        let mapped = ContentMapping.map(try content(Fixture.text("hello")))
        #expect(mapped == MappedContent(text: "hello", attachmentLabel: nil))
    }

    @Test("Service events are flagged, so they render as centred lines")
    func service() throws {
        let mapped = ContentMapping.map(try content(#"{"@type":"messagePinMessage","message_id":3}"#))
        #expect(mapped.isService)
        #expect(mapped.text == "pinned a message")
    }

    @Test("Unknown content gets an honest label, never an empty bubble")
    func unsupported() throws {
        let mapped = ContentMapping.map(try content(#"{"@type":"messageUnsupported"}"#))
        #expect(mapped.text.isEmpty)
        #expect(mapped.attachmentLabel?.isEmpty == false)
    }
}

@Suite("MediaMapping")
struct MediaMappingTests {

    @Test("Waveform unpacks 5-bit samples across byte boundaries")
    func waveformDecoding() {
        // Samples 31, 0, 21, 10 packed LSB-first: 11111 00000 10101 01010
        // → bits (LSB first): 1111100000101010 1010 → bytes 0x1F, 0x54, 0x05
        let samples = MediaMapping.waveform(Data([0x1F, 0x54, 0x05]))
        #expect(Array(samples.prefix(4)) == [31, 0, 21, 10])
    }

    @Test("Waveform of empty data is empty, not a crash")
    func emptyWaveform() {
        #expect(MediaMapping.waveform(Data()).isEmpty)
    }
}
