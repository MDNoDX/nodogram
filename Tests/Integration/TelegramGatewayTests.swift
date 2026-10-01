//  Integration tests against the REAL TDLib binary.
//
//  These need no Telegram account and make no network calls: they exercise
//  behaviour TDLib exhibits locally before any login. They are the regression
//  net for the findings recorded in Documentation/ARCHITECTURE.md §1.

import Testing
import Foundation
@testable import NodogramTelegram
import NodogramDomain

@Suite("TelegramGateway (real TDLib)", .serialized)
struct TelegramGatewayTests {

    @Test("TDLib loads and reports the version pinned in UPSTREAM.md")
    func reportsPinnedVersion() async throws {
        let gateway = TelegramGateway()
        defer { gateway.shutdown() }

        let version = try await gateway.tdlibVersion()

        // If this fails, the pin moved without UPSTREAM.md being updated.
        #expect(version == "1.8.67")
    }

    @Test("Option queries succeed before setTdlibParameters")
    func optionsAnswerBeforeInitialization() async throws {
        // This is the corrected finding: an earlier assumption held that TDLib
        // answers nothing until initialized. It does answer option queries.
        let gateway = TelegramGateway()
        defer { gateway.shutdown() }

        let version = try await gateway.tdlibVersion()
        #expect(!version.isEmpty)
        #expect(version != "unknown")
    }

    @Test("An uninitialized client reports waiting for parameters")
    func startsAwaitingParameters() async throws {
        let gateway = TelegramGateway()
        defer { gateway.shutdown() }

        let state = try await gateway.currentAuthorizationState()
        #expect(state == .waitingForParameters)
    }

    @Test("Account requests before initialization fail fast, and are recognised")
    func accountRequestsFailFast() async throws {
        // TDLib returns error 400 rather than hanging, which is what lets the
        // gateway model requests as ordinary async calls.
        let gateway = TelegramGateway()
        defer { gateway.shutdown() }

        await #expect(throws: DomainError.notInitialized) {
            try await gateway.setPhoneNumber("+10000000000")
        }
    }

    @Test("The update stream delivers the version option")
    func updateStreamDeliversOptions() async throws {
        // Proves the ordered event stream is actually wired to TDLib's callback,
        // which is the backbone of the sync layer.
        let gateway = TelegramGateway()
        defer { gateway.shutdown() }

        let received: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                // Events arrive in per-frame batches; order within a batch is
                // the order TDLib sent them.
                for await batch in gateway.events {
                    for case .optionReceived(let name, let value) in batch where name == "version" {
                        return value
                    }
                }
                return nil
            }
            group.addTask {
                // Bound the wait so a regression fails rather than hangs.
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        #expect(received == "1.8.67")
    }
}
