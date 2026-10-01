//  The read-state type is the guard against the brief's hardest rule:
//  "Do NOT invent read timestamps when the protocol does not provide them."
//  These tests pin that guarantee down.

import Testing
import Foundation
@testable import NodogramDomain

@Suite("MessageReadDate")
struct MessageReadDateTests {

    @Test("A precise date exists only in the .read case")
    func preciseDateOnlyWhenRead() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(MessageReadDate.read(moment).preciseDate == moment)

        // The whole point: no other case can produce a timestamp.
        #expect(MessageReadDate.unread.preciseDate == nil)
        #expect(MessageReadDate.tooOld.preciseDate == nil)
        #expect(MessageReadDate.recipientPrivacyRestricted.preciseDate == nil)
        #expect(MessageReadDate.ownPrivacyRestricted.preciseDate == nil)
    }

    @Test("Every case except .unread counts as read")
    func readnessIsSeparateFromTimeAvailability() {
        // A message can be known-read while its time is unavailable. Conflating
        // these would either lose the read state or invent a time.
        #expect(MessageReadDate.read(.now).isRead)
        #expect(MessageReadDate.tooOld.isRead)
        #expect(MessageReadDate.recipientPrivacyRestricted.isRead)
        #expect(MessageReadDate.ownPrivacyRestricted.isRead)
        #expect(!MessageReadDate.unread.isRead)
    }

    @Test("Privacy-withheld is distinguishable from an expired timestamp")
    func privacyIsDistinctFromExpiry() {
        // These need different UI copy: one is a setting the user can change,
        // the other is server retention they cannot.
        #expect(MessageReadDate.recipientPrivacyRestricted.isPrivacyWithheld)
        #expect(MessageReadDate.ownPrivacyRestricted.isPrivacyWithheld)
        #expect(!MessageReadDate.tooOld.isPrivacyWithheld)
        #expect(!MessageReadDate.read(.now).isPrivacyWithheld)
        #expect(!MessageReadDate.unread.isPrivacyWithheld)
    }

    @Test("Viewers carry their own view dates for 'Read by'")
    func viewerCarriesDate() {
        let when = Date(timeIntervalSince1970: 1_700_000_500)
        let viewer = MessageViewer(userID: UserID(42), viewDate: when)
        #expect(viewer.userID == UserID(42))
        #expect(viewer.viewDate == when)
    }
}

@Suite("ComposerState")
struct ComposerStateTests {

    @Test("States that block typing do so deliberately")
    func inputAcceptance() {
        #expect(ComposerState.empty.acceptsInput)
        #expect(ComposerState.typing.acceptsInput)
        #expect(ComposerState.replying(to: MessageID(1)).acceptsInput)
        #expect(ComposerState.editing(MessageID(1)).acceptsInput)

        // In flight or mid-forward: accepting edits here would let UI state and
        // the pending operation diverge.
        #expect(!ComposerState.sending.acceptsInput)
        #expect(!ComposerState.offlinePending.acceptsInput)
        #expect(!ComposerState.forwarding(from: ChatID(1), messages: []).acceptsInput)
    }

    @Test("Only meaningful work is persisted as a draft")
    func draftability() {
        #expect(ComposerState.typing.isDraftable)
        #expect(ComposerState.replying(to: MessageID(7)).isDraftable)
        #expect(ComposerState.offlinePending.isDraftable)
        #expect(ComposerState.failed(reason: "network").isDraftable)

        // An empty composer or an in-flight send is not a draft.
        #expect(!ComposerState.empty.isDraftable)
        #expect(!ComposerState.sending.isDraftable)
    }
}

@Suite("ConnectionState")
struct ConnectionStateTests {

    @Test("A healthy connection shows no indicator")
    func quietWhenConnected() {
        // The brief explicitly forbids constant banners.
        #expect(!ConnectionState.connected.isWorthShowing)
        #expect(ConnectionState.connecting.isWorthShowing)
        #expect(ConnectionState.offline.isWorthShowing)
        #expect(ConnectionState.updating.isWorthShowing)
    }
}

@Suite("DomainError")
struct DomainErrorTests {

    @Test("User-facing copy never leaks protocol detail")
    func copyIsClean() {
        let error = DomainError.protocolFailure(code: 420, message: "FLOOD_WAIT_30")
        #expect(!error.userFacingDescription.contains("420"))
        #expect(!error.userFacingDescription.contains("FLOOD_WAIT"))
        // ...but the detail is still retrievable behind a "Details" affordance.
        #expect(error.technicalDetail?.contains("FLOOD_WAIT_30") == true)
    }

    @Test("Rate limiting reports the actual wait")
    func rateLimitCopy() {
        let error = DomainError.rateLimited(retryAfter: 30)
        #expect(error.userFacingDescription.contains("30"))
    }

    @Test("Errors without technical detail expose none")
    func noSpuriousDetail() {
        #expect(DomainError.networkUnavailable.technicalDetail == nil)
        #expect(DomainError.notAuthorized.technicalDetail == nil)
    }
}
