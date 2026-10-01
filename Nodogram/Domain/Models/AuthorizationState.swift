//  Authorization state.
//
//  Mirrors TDLib's own `updateAuthorizationState` rather than inventing a
//  parallel login flow — any divergence desynchronises login.
//  See Documentation/ARCHITECTURE.md §4.

import Foundation

public enum AuthorizationState: Hashable, Sendable {
    /// TDLib needs `setTdlibParameters` before it will do anything with an
    /// account. Option queries still work in this state.
    case waitingForParameters
    case waitingForPhoneNumber
    case waitingForCode(CodeInfo)
    case waitingForPassword(PasswordInfo)
    case waitingForRegistration
    case ready
    case loggingOut
    case closing
    case closed

    public struct CodeInfo: Hashable, Sendable {
        public let phoneNumber: String
        public let codeLength: Int
        /// How the code was delivered, so the UI can say "check Telegram"
        /// rather than always "check your SMS".
        public let deliveryHint: Delivery

        public enum Delivery: Hashable, Sendable {
            case telegramMessage
            case sms
            case call
            case flashCall
            case other
        }

        public init(phoneNumber: String, codeLength: Int, deliveryHint: Delivery) {
            self.phoneNumber = phoneNumber
            self.codeLength = codeLength
            self.deliveryHint = deliveryHint
        }
    }

    public struct PasswordInfo: Hashable, Sendable {
        public let hint: String?
        public let hasRecoveryEmail: Bool

        public init(hint: String?, hasRecoveryEmail: Bool) {
            self.hint = hint
            self.hasRecoveryEmail = hasRecoveryEmail
        }
    }

    public var isAuthorized: Bool { self == .ready }
}
