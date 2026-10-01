//  Pins down the one assumption the whole sync layer rests on: that TDLib's raw
//  update JSON decodes into TDLibKit's typed `Update` enum with a snake_case
//  decoder. If a TDLibKit upgrade breaks this, every chat silently vanishes —
//  so it is tested directly rather than discovered through an empty window.

import Testing
import Foundation
import TDLibKit
@testable import NodogramTelegram

@Suite("Update decoding")
struct UpdateDecodingTests {

    @Test("A raw updateChatTitle decodes to the typed case")
    func decodesChatTitle() throws {
        let json = #"{"@type":"updateChatTitle","chat_id":-1001234567890,"title":"Backend team"}"#
        let update = try TelegramGateway.decodeUpdate(Data(json.utf8))
        guard case .updateChatTitle(let value) = update else {
            Issue.record("decoded as \(String(describing: update))")
            return
        }
        #expect(value.chatId == -1001234567890)
        #expect(value.title == "Backend team")
    }

    @Test("A raw updateChatReadInbox decodes, including snake_case fields")
    func decodesReadInbox() throws {
        let json = #"{"@type":"updateChatReadInbox","chat_id":42,"last_read_inbox_message_id":1048576,"unread_count":7}"#
        let update = try TelegramGateway.decodeUpdate(Data(json.utf8))
        guard case .updateChatReadInbox(let value) = update else {
            Issue.record("decoded as \(String(describing: update))")
            return
        }
        #expect(value.unreadCount == 7)
        #expect(value.lastReadInboxMessageId == 1048576)
    }

    @Test("A raw updateDeleteMessages keeps the from_cache flag")
    func decodesDeletionFlags() throws {
        // from_cache distinguishes "evicted from TDLib's cache" from "deleted".
        // Treating eviction as deletion would make messages disappear wrongly.
        let json = #"{"@type":"updateDeleteMessages","chat_id":1,"message_ids":[10,11],"is_permanent":false,"from_cache":true}"#
        let update = try TelegramGateway.decodeUpdate(Data(json.utf8))
        guard case .updateDeleteMessages(let value) = update else {
            Issue.record("decoded as \(String(describing: update))")
            return
        }
        #expect(value.fromCache)
        #expect(!value.isPermanent)
        #expect(value.messageIds == [10, 11])
    }
}
