//  TelegramGateway — the single point in Nodogram that touches TDLib.
//
//  WHY `@unchecked Sendable` AND NOT AN ACTOR
//  ------------------------------------------
//  `TDLibKit.TDLibClient` is not Sendable, and its methods are
//  `nonisolated async`. Holding it in an `actor` therefore does NOT help: the
//  call still *sends* the client out of the actor's isolation domain and fails
//  to compile under Swift 6.
//
//  Confinement is sound because of TDLib's documented C contract
//  (td/telegram/td_json_client.h), verified by reading the header:
//
//    - "share the client_id with other threads, which will be able to send
//       requests via td_send"           -> sending is thread-safe
//    - "This function [td_receive] must not be called simultaneously from two
//       different threads"              -> one receiver, owned by TDLibClientManager
//    - "all updates and responses ... must be applied in the order they were
//       received for consistency"       -> updates must never be processed in parallel
//    - "All TDLib client instances must be closed before application
//       termination"                    -> shutdown() is mandatory, not optional
//
//  Every method here returns Sendable values only, so the client never escapes.
//
//  See Documentation/ARCHITECTURE.md §1.3 and §4.

import Foundation
import NodogramDomain
import TDLibKit

/// An ordered event from TDLib, already translated into domain terms.
public enum TelegramEvent: Sendable {
    case authorizationStateChanged(NodogramDomain.AuthorizationState)
    case connectionStateChanged(NodogramDomain.ConnectionState)
    case optionReceived(name: String, value: String)
}

public final class TelegramGateway: @unchecked Sendable {

    /// The process-wide TDLib manager.
    ///
    /// There must be EXACTLY ONE of these per process. Each `TDLibClientManager`
    /// starts its own `td_receive` loop, and TDLib's contract states that
    /// `td_receive` "must not be called simultaneously from two different
    /// threads" — two managers abort the process (verified: SIGABRT).
    ///
    /// This is not merely a constraint to work around. TDLib's model is one
    /// receive loop with many clients, which is exactly what multi-account
    /// isolation needs (brief §40): one client per account, one manager overall.
    /// `nonisolated(unsafe)` because `TDLibClientManager` is not `Sendable`,
    /// yet a single shared instance is exactly what TDLib requires. It is safe
    /// here because the instance is created once and never reassigned, its
    /// client registry is a concurrent dictionary, and `td_send` is documented
    /// as callable from any thread. Making it an `actor` is not possible: its
    /// methods are synchronous and are called from TDLib's own receive thread.
    private nonisolated(unsafe) static let sharedManager = TDLibClientManager()

    /// This gateway's own client. One per account.
    private let client: TDLibClient

    /// The single ordered event stream. TDLib's contract requires updates be
    /// applied in receive order, so there is exactly one stream with exactly
    /// one intended consumer — never a parallel fan-out.
    public let events: AsyncStream<TelegramEvent>
    private let continuation: AsyncStream<TelegramEvent>.Continuation

    public init() {
        let (stream, continuation) = AsyncStream<TelegramEvent>.makeStream(
            // Buffer rather than drop: losing an update would desynchronise
            // state, which is worse than briefly using more memory.
            bufferingPolicy: .unbounded
        )
        self.events = stream
        self.continuation = continuation

        self.client = Self.sharedManager.createClient { data, _ in
            // Invoked on TDLibKit's per-client serial queue — already ordered.
            Self.handle(data: data, continuation: continuation)
        }
    }

    // MARK: - Lifecycle

    /// Sends `setTdlibParameters`, without which every account request fails
    /// with error 400 (verified; see ARCHITECTURE.md §1.2).
    public func initialize(
        credentials: TelegramCredentials,
        databaseDirectory: URL,
        filesDirectory: URL
    ) async throws(DomainError) {
        do {
            _ = try await client.setTdlibParameters(
                apiHash: credentials.apiHash,
                apiId: credentials.apiID,
                applicationVersion: Self.applicationVersion,
                databaseDirectory: databaseDirectory.path,
                databaseEncryptionKey: Data(),
                deviceModel: Self.deviceModel,
                filesDirectory: filesDirectory.path,
                systemLanguageCode: Self.systemLanguageCode,
                systemVersion: Self.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: false,
                useTestDc: false
            )
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Closes THIS gateway's client. Required before termination, per TDLib's
    /// contract ("All TDLib client instances must be closed before application
    /// termination to ensure data consistency").
    ///
    /// Deliberately closes only our own client rather than calling
    /// `closeClients()`, which closes every client in the process and then
    /// busy-waits on them — that would stall other accounts and spin the CPU.
    public func shutdown() {
        try? client.close { _ in }
        continuation.finish()
    }

    // MARK: - Requests

    public func tdlibVersion() async throws(DomainError) -> String {
        try await stringOption("version") ?? "unknown"
    }

    public func setPhoneNumber(_ phoneNumber: String) async throws(DomainError) {
        do {
            _ = try await client.setAuthenticationPhoneNumber(
                phoneNumber: phoneNumber,
                settings: nil
            )
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    public func checkCode(_ code: String) async throws(DomainError) {
        do {
            _ = try await client.checkAuthenticationCode(code: code)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    public func checkPassword(_ password: String) async throws(DomainError) {
        do {
            _ = try await client.checkAuthenticationPassword(password: password)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    public func logOut() async throws(DomainError) {
        do {
            _ = try await client.logOut()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Asks TDLib for the current authorization state, rather than waiting for
    /// an update that may already have been emitted before we subscribed.
    public func currentAuthorizationState() async throws(DomainError)
        -> NodogramDomain.AuthorizationState? {
        do {
            return AuthorizationMapping.map(try await client.getAuthorizationState())
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    private func stringOption(_ name: String) async throws(DomainError) -> String? {
        do {
            guard case .optionValueString(let value) = try await client.getOption(name: name) else {
                return nil
            }
            return value.value
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Update handling

    /// Parses raw update JSON. Kept `static` so it cannot accidentally capture
    /// `self` (and therefore the non-Sendable client) into the callback.
    private static func handle(
        data: Data,
        continuation: AsyncStream<TelegramEvent>.Continuation
    ) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["@type"] as? String
        else { return }

        switch type {
        case "updateAuthorizationState":
            guard
                let nested = json["authorization_state"] as? [String: Any],
                let stateType = nested["@type"] as? String
            else { return }
            if let state = mapAuthorizationStateName(stateType, payload: nested) {
                continuation.yield(.authorizationStateChanged(state))
            }

        case "updateConnectionState":
            guard
                let nested = json["state"] as? [String: Any],
                let stateType = nested["@type"] as? String
            else { return }
            continuation.yield(.connectionStateChanged(mapConnectionStateName(stateType)))

        case "updateOption":
            guard
                let name = json["name"] as? String,
                let wrapper = json["value"] as? [String: Any],
                let value = wrapper["value"]
            else { return }
            continuation.yield(.optionReceived(name: name, value: String(describing: value)))

        default:
            break
        }
    }

    /// Maps by `@type` name from the raw JSON.
    ///
    /// The code/password states carry detail we cannot read reliably from raw
    /// JSON here, so they are reported without it; the view model then asks
    /// TDLib via `currentAuthorizationState()` for the typed version. This
    /// keeps one decoder of record instead of two that could disagree.
    private static func mapAuthorizationStateName(
        _ name: String,
        payload: [String: Any]
    ) -> NodogramDomain.AuthorizationState? {
        switch name {
        case "authorizationStateWaitTdlibParameters": return .waitingForParameters
        case "authorizationStateWaitPhoneNumber": return .waitingForPhoneNumber
        case "authorizationStateWaitRegistration": return .waitingForRegistration
        case "authorizationStateReady": return .ready
        case "authorizationStateLoggingOut": return .loggingOut
        case "authorizationStateClosing": return .closing
        case "authorizationStateClosed": return .closed
        case "authorizationStateWaitCode":
            return .waitingForCode(
                .init(phoneNumber: "", codeLength: 5, deliveryHint: .other))
        case "authorizationStateWaitPassword":
            let hint = (payload["password_hint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return .waitingForPassword(
                .init(hint: hint,
                      hasRecoveryEmail: payload["has_recovery_email_address"] as? Bool ?? false))
        default:
            return nil
        }
    }

    private static func mapConnectionStateName(
        _ name: String
    ) -> NodogramDomain.ConnectionState {
        switch name {
        case "connectionStateReady": return .connected
        case "connectionStateConnecting": return .connecting
        case "connectionStateConnectingToProxy": return .connectingToProxy
        case "connectionStateUpdating": return .updating
        case "connectionStateWaitingForNetwork": return .offline
        default: return .connecting
        }
    }

    // MARK: - Device description sent to Telegram

    private static var applicationVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.1.0"
    }

    private static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    private static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static var systemLanguageCode: String {
        Locale.preferredLanguages.first ?? "en"
    }
}
