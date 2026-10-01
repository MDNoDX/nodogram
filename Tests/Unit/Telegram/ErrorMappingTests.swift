//  The mapping layer is the boundary that stops TDLib types escaping upward.
//  These tests cover the translations whose behaviour was verified against a
//  real TDLib binary (Documentation/ARCHITECTURE.md §1.2).

import Testing
import Foundation
@testable import NodogramTelegram
import NodogramDomain

@Suite("ErrorMapping")
struct ErrorMappingTests {

    @Test("The pre-initialization error is recognised, not surfaced as a failure")
    func notInitializedIsRecognised() {
        // Verified real response: TDLib returns exactly this before
        // setTdlibParameters, and it is transient rather than user-facing.
        let mapped = ErrorMapping.map(
            code: 400,
            message: "Initialization parameters are needed: call setTdlibParameters first"
        )
        #expect(mapped == .notInitialized)
    }

    @Test("FLOOD_WAIT carries its delay through")
    func floodWaitExtractsSeconds() {
        let mapped = ErrorMapping.map(code: 420, message: "FLOOD_WAIT_42")
        guard case .rateLimited(let retryAfter) = mapped else {
            Issue.record("expected .rateLimited, got \(mapped)")
            return
        }
        #expect(retryAfter == 42)
    }

    @Test("A malformed FLOOD_WAIT still yields a usable delay")
    func floodWaitFallsBack() {
        // Better a conservative default than crashing or retrying instantly.
        let mapped = ErrorMapping.map(code: 420, message: "FLOOD_WAIT")
        guard case .rateLimited(let retryAfter) = mapped else {
            Issue.record("expected .rateLimited, got \(mapped)")
            return
        }
        #expect(retryAfter == 60)
    }

    @Test("Authentication failures map to specific, actionable cases")
    func authenticationErrors() {
        #expect(ErrorMapping.map(code: 400, message: "PHONE_NUMBER_INVALID") == .invalidPhoneNumber)
        #expect(ErrorMapping.map(code: 400, message: "PHONE_CODE_INVALID") == .invalidCode)
        #expect(ErrorMapping.map(code: 400, message: "PHONE_CODE_EXPIRED") == .invalidCode)
        #expect(ErrorMapping.map(code: 400, message: "PASSWORD_HASH_INVALID") == .invalidPassword)
        #expect(ErrorMapping.map(code: 401, message: "UNAUTHORIZED") == .notAuthorized)
    }

    @Test("Unrecognised errors keep their detail for the Details disclosure")
    func unknownErrorsRetainDetail() {
        let mapped = ErrorMapping.map(code: 500, message: "SOMETHING_NEW")
        guard case .protocolFailure(let code, let message) = mapped else {
            Issue.record("expected .protocolFailure, got \(mapped)")
            return
        }
        #expect(code == 500)
        #expect(message == "SOMETHING_NEW")
    }
}

@Suite("TelegramCredentials")
struct TelegramCredentialsTests {

    /// A stand-in bundle so credential validation is testable without a real
    /// app bundle.
    private final class StubBundle: Bundle, @unchecked Sendable {
        private let values: [String: String]
        init(values: [String: String]) {
            self.values = values
            super.init()
        }
        required init?(coder: NSCoder) { fatalError("unused") }
        override func object(forInfoDictionaryKey key: String) -> Any? {
            values[key]
        }
    }

    @Test("Absent credentials explain the fix rather than failing opaquely")
    func missingCredentialsAreExplained() {
        let result = TelegramCredentials.fromBundle(StubBundle(values: [:]))
        guard case .failure(let error) = result,
              case .missingCredentials(let detail) = error else {
            Issue.record("expected .missingCredentials")
            return
        }
        // The message must name the file and the portal, or the user is stuck.
        #expect(detail.contains("Secrets.xcconfig"))
        #expect(detail.contains("my.telegram.org"))
    }

    @Test("A non-numeric api_id is caught at load, not at login")
    func nonNumericIDRejected() {
        let result = TelegramCredentials.fromBundle(StubBundle(values: [
            "TelegramAPIID": "not-a-number",
            "TelegramAPIHash": String(repeating: "a", count: 32),
        ]))
        guard case .failure = result else {
            Issue.record("expected failure for non-numeric api_id")
            return
        }
    }

    @Test("A wrong-length api_hash is caught early")
    func shortHashRejected() {
        // Catching this here beats a confusing authentication failure later.
        let result = TelegramCredentials.fromBundle(StubBundle(values: [
            "TelegramAPIID": "123456",
            "TelegramAPIHash": "tooshort",
        ]))
        guard case .failure(let error) = result,
              case .missingCredentials(let detail) = error else {
            Issue.record("expected .missingCredentials")
            return
        }
        #expect(detail.contains("32"))
    }

    @Test("Well-formed credentials load, ignoring stray whitespace")
    func validCredentialsLoad() {
        let hash = String(repeating: "a", count: 32)
        let result = TelegramCredentials.fromBundle(StubBundle(values: [
            "TelegramAPIID": "  123456  ",
            "TelegramAPIHash": "  \(hash)  ",
        ]))
        guard case .success(let credentials) = result else {
            Issue.record("expected success")
            return
        }
        #expect(credentials.apiID == 123456)
        #expect(credentials.apiHash == hash)
    }
}
