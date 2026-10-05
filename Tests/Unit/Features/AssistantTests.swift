//  The assistant's local, no-AI parts: the transcript sent to the model
//  (anonymised) and the stats computed on this Mac.

import Foundation
import Testing
@testable import NodogramFeatures
import NodogramDomain

@MainActor
@Suite("Assistant local analysis")
struct AssistantTests {

    private func msg(_ id: Int64, _ text: String, mine: Bool, sender: Int64 = 2, minutesAfter: Double = 0) -> Message {
        Message(id: MessageID(id), chatID: ChatID(mine ? 2 : 2), senderID: UserID(mine ? 1 : sender),
                senderName: mine ? "Me" : "Them", text: text,
                date: Date(timeIntervalSince1970: 1_760_000_000 + minutesAfter * 60), isOutgoing: mine)
    }

    @Test("Transcript labels Me/Them and never leaks names")
    func transcript() {
        let text = AppModel.transcript([msg(1, "Salom", mine: false), msg(2, "Vaalaykum", mine: true)], isGroup: false)
        #expect(text.contains("Them: Salom"))
        #expect(text.contains("Me: Vaalaykum"))
        #expect(!text.contains("Nodir"))
    }

    @Test("Group members become Person A, Person B — not their names")
    func groupAnonymised() {
        let text = AppModel.transcript([
            msg(1, "hi", mine: false, sender: 5), msg(2, "yo", mine: false, sender: 9),
        ], isGroup: true)
        #expect(text.contains("Person A: hi"))
        #expect(text.contains("Person B: yo"))
    }

    @Test("Deleted messages are marked in the transcript")
    func deletedMarked() {
        var m = msg(1, "oops", mine: false)
        m.deletedAt = Date()
        #expect(AppModel.transcript([m], isGroup: false).contains("(they deleted this)"))
    }

    @Test("Stats count who started and reply times")
    func stats() {
        let messages = [
            msg(1, "hi", mine: false, minutesAfter: 0),
            msg(2, "hey", mine: true, minutesAfter: 2),      // my reply: 2 min
            msg(3, "u there", mine: false, minutesAfter: 10 * 60), // they start again (>6h gap)
        ]
        let s = AppModel.stats(messages)
        #expect(s.mine == 1)
        #expect(s.theirs == 2)
        #expect(s.theyStarted == 1)
        #expect(s.myMedianReply == 120)
    }
}
