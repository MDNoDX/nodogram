//  The archive is what keeps messages others delete. These tests pin down its
//  promises: it keeps what it received, marks rather than drops on deletion,
//  never invents what it never saw, and stores content only in encrypted form.

import Testing
import Foundation
import CryptoKit
@testable import NodogramCore
import NodogramDomain

@Suite("MessageArchive")
struct MessageArchiveTests {

    private func makeArchive() throws -> (MessageArchive, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("archive.sqlite")
        return (try MessageArchive(path: path.path, key: SymmetricKey(size: .bits256)), path)
    }

    private func message(_ id: Int64, _ text: String, chat: Int64 = 1) -> Message {
        Message(id: MessageID(id), chatID: ChatID(chat), senderID: UserID(7), senderName: "Ali",
                text: text, date: Date(timeIntervalSince1970: 1_760_000_000 + Double(id)),
                entities: [TextEntity(offset: 0, length: 4, kind: .bold)])
    }

    @Test("A deleted message comes back with its text, marked deleted")
    func deletedMessageIsKept() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(10, "Meeting tomorrow at 10")])

        let kept = await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(10)])
        let copy = try #require(kept.first)
        #expect(copy.text == "Meeting tomorrow at 10")
        #expect(copy.senderName == "Ali")
        #expect(copy.isDeleted)
        #expect(copy.entities.first?.kind == .bold)
    }

    @Test("A message never received is not invented")
    func unknownMessageIsNotInvented() async throws {
        let (archive, _) = try makeArchive()
        let kept = await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(999)])
        #expect(kept.isEmpty)
    }

    @Test("Deleted messages are found again when the chat is reopened")
    func deletedMessagesMergeIntoHistory() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(10, "a"), message(20, "b"), message(30, "c")])
        _ = await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(20)])

        let inRange = await archive.deletedMessages(in: ChatID(1), ids: 10...30)
        #expect(inRange.map(\.id) == [MessageID(20)])
        let outOfRange = await archive.deletedMessages(in: ChatID(1), ids: 21...30)
        #expect(outOfRange.isEmpty)
    }

    @Test("An edit cannot overwrite what was first received")
    func firstCopyWins() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(10, "original")])
        await archive.record([message(10, "edited later")])
        let kept = await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(10)])
        #expect(kept.first?.text == "original")
    }

    @Test("Message text is never stored in the clear")
    func contentIsEncrypted() async throws {
        let (archive, path) = try makeArchive()
        await archive.record([message(10, "secret-plaintext-marker")])
        _ = await archive.statistics()  // ensure the write has landed

        let raw = try Data(contentsOf: path)
        #expect(raw.range(of: Data("secret-plaintext-marker".utf8)) == nil)
    }

    @Test("A different key cannot read the archive")
    func wrongKeyReadsNothing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("archive.sqlite").path

        let writer = try MessageArchive(path: path, key: SymmetricKey(size: .bits256))
        await writer.record([message(10, "x")])
        _ = await writer.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(10)])

        let reader = try MessageArchive(path: path, key: SymmetricKey(size: .bits256))
        #expect(await reader.deletedMessages(in: ChatID(1), ids: 0...100).isEmpty)
    }

    @Test("Pending sends and other chats are kept apart")
    func pendingAndOtherChatsIgnored() async throws {
        let (archive, _) = try makeArchive()
        var pending = message(10, "sending")
        pending.sendState = .sending
        await archive.record([pending, message(11, "other chat", chat: 2)])

        #expect(await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(10)]).isEmpty)
        #expect(await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(11)]).isEmpty)
    }

    @Test("Erase removes everything")
    func erase() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(10, "a")])
        _ = await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(10)])
        await archive.eraseAll()
        #expect(await archive.statistics() == .init(received: 0, deleted: 0))
    }

    @Test("Edits are kept as versions, original first")
    func editHistory() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(20, "See you at 5")])
        await archive.recordEdit(chatID: ChatID(1), messageID: MessageID(20), text: "See you at 6")
        await archive.recordEdit(chatID: ChatID(1), messageID: MessageID(20), text: "See you at 6")   // repeat ignored
        await archive.recordEdit(chatID: ChatID(1), messageID: MessageID(20), text: "Cancelled")
        let versions = await archive.editHistory(chatID: ChatID(1), messageID: MessageID(20))
        #expect(versions.map(\.text) == ["See you at 5", "See you at 6", "Cancelled"])
    }

    @Test("Edits of a message never received are not tracked")
    func editWithoutOriginal() async throws {
        let (archive, _) = try makeArchive()
        await archive.recordEdit(chatID: ChatID(1), messageID: MessageID(99), text: "new")
        #expect(await archive.editHistory(chatID: ChatID(1), messageID: MessageID(99)).isEmpty)
    }

    @Test("Recently deleted lists newest deletions across chats")
    func recentlyDeleted() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(1, "one", chat: 1), message(2, "two", chat: 2), message(3, "three", chat: 2)])
        _ = await archive.markDeleted(chatID: ChatID(1), messageIDs: [MessageID(1)], at: Date(timeIntervalSince1970: 100))
        _ = await archive.markDeleted(chatID: ChatID(2), messageIDs: [MessageID(3)], at: Date(timeIntervalSince1970: 200))
        let recent = await archive.recentlyDeleted()
        #expect(recent.map(\.text) == ["three", "one"])
    }

    @Test("Erasing removes edit history too")
    func eraseRemovesEdits() async throws {
        let (archive, _) = try makeArchive()
        await archive.record([message(30, "a")])
        await archive.recordEdit(chatID: ChatID(1), messageID: MessageID(30), text: "b")
        await archive.eraseAll()
        #expect(await archive.editHistory(chatID: ChatID(1), messageID: MessageID(30)).isEmpty)
    }

    @Test("Derived keys are stable per purpose and differ between purposes")
    func derivedKeys() {
        let master = SymmetricKey(size: .bits256)
        let a1 = KeychainKey.derive(from: master, purpose: "message-archive")
        let a2 = KeychainKey.derive(from: master, purpose: "message-archive")
        let b = KeychainKey.derive(from: master, purpose: "other")
        #expect(a1 == a2)
        #expect(a1 != b)
        #expect(a1 != master)
    }
}
