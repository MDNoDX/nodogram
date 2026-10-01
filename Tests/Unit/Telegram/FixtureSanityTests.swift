import Testing
import Foundation
import TDLibKit
@testable import NodogramTelegram

/// If these fail, every other cache test is meaningless — so they run first and
/// report precisely which key the decoder rejected.
@Suite("Fixtures decode")
struct FixtureSanityTests {
    @Test func chatFixtureDecodes() throws {
        _ = try Fixture.update(Fixture.newChat(id: 1, title: "A", positions: [Fixture.position(order: 5)]))
    }
    @Test func messageFixtureDecodes() throws {
        _ = try Fixture.update(#"{"@type":"updateNewMessage","message":\#(Fixture.message(id: 1, chatId: 1, content: Fixture.text("hi")))}"#)
    }
    @Test func userFixtureDecodes() throws {
        _ = try Fixture.update(Fixture.user(id: 7, first: "Ali"))
    }
}
