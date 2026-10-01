//  Domain-level errors.
//
//  Protocol errors are translated into these at the gateway boundary so that no
//  TDLib type escapes upward (Documentation/ARCHITECTURE.md §2). Each case
//  carries enough information for honest user-facing copy — the brief forbids
//  showing stack traces or raw protocol errors (brief §71).

import Foundation

public enum DomainError: Error, Hashable, Sendable {
    /// TDLib has not been initialized yet. Recoverable, not a user-facing
    /// failure: it means `setTdlibParameters` has not completed.
    /// Observed as TDLib error 400 "Initialization parameters are needed".
    case notInitialized

    /// Telegram API credentials are absent or malformed.
    case missingCredentials(detail: String)

    case notAuthorized
    case networkUnavailable
    case rateLimited(retryAfter: TimeInterval)
    case invalidPhoneNumber
    case invalidCode
    case invalidPassword

    /// An error Telegram reported that we do not specifically handle. The raw
    /// text is kept for a "Details" affordance, never shown by default.
    case protocolFailure(code: Int, message: String)

    case storageFailure(detail: String)

    /// Copy suitable for showing a user directly: says what happened and what
    /// happens next, with no jargon.
    public var userFacingDescription: String {
        switch self {
        case .notInitialized:
            return "Still starting up. This will clear in a moment."
        case .missingCredentials:
            return "Nodogram needs your Telegram API credentials before it can connect."
        case .notAuthorized:
            return "You're signed out. Sign in to continue."
        case .networkUnavailable:
            return "You're offline. Nodogram will sync when the connection returns."
        case .rateLimited(let retryAfter):
            let seconds = Int(retryAfter.rounded(.up))
            return "Telegram asked us to slow down. Trying again in \(seconds)s."
        case .invalidPhoneNumber:
            return "That phone number doesn't look right. Include your country code."
        case .invalidCode:
            return "That code wasn't accepted. Check it and try again."
        case .invalidPassword:
            return "That password wasn't accepted."
        case .protocolFailure:
            return "Telegram couldn't complete that request."
        case .storageFailure:
            return "Nodogram couldn't save that locally."
        }
    }

    /// The technical detail, for the "Details" disclosure only.
    public var technicalDetail: String? {
        switch self {
        case .protocolFailure(let code, let message):
            return "Telegram error \(code): \(message)"
        case .missingCredentials(let detail), .storageFailure(let detail):
            return detail
        default:
            return nil
        }
    }
}
