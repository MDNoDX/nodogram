//  Maps TDLib authorization states to the domain's own.

import Foundation
import NodogramDomain
import TDLibKit

enum AuthorizationMapping {
    static func map(_ state: TDLibKit.AuthorizationState) -> NodogramDomain.AuthorizationState? {
        switch state {
        case .authorizationStateWaitTdlibParameters:
            return .waitingForParameters
        case .authorizationStateWaitPhoneNumber:
            return .waitingForPhoneNumber
        case .authorizationStateWaitCode(let info):
            return .waitingForCode(mapCodeInfo(info.codeInfo))
        case .authorizationStateWaitPassword(let info):
            return .waitingForPassword(
                .init(
                    hint: info.passwordHint.isEmpty ? nil : info.passwordHint,
                    hasRecoveryEmail: info.hasRecoveryEmailAddress
                )
            )
        case .authorizationStateWaitRegistration:
            return .waitingForRegistration
        case .authorizationStateReady:
            return .ready
        case .authorizationStateLoggingOut:
            return .loggingOut
        case .authorizationStateClosing:
            return .closing
        case .authorizationStateClosed:
            return .closed
        default:
            // TDLib has states we deliberately do not model (e.g. email
            // address flows). Returning nil leaves the current state intact
            // rather than inventing a transition.
            return nil
        }
    }

    private static func mapCodeInfo(
        _ info: TDLibKit.AuthenticationCodeInfo
    ) -> NodogramDomain.AuthorizationState.CodeInfo {
        let delivery: NodogramDomain.AuthorizationState.CodeInfo.Delivery
        var length = 5

        switch info.type {
        case .authenticationCodeTypeTelegramMessage(let t):
            delivery = .telegramMessage
            length = Int(t.length)
        case .authenticationCodeTypeSms(let t):
            delivery = .sms
            length = Int(t.length)
        case .authenticationCodeTypeCall(let t):
            delivery = .call
            length = Int(t.length)
        case .authenticationCodeTypeFlashCall:
            delivery = .flashCall
        default:
            delivery = .other
        }

        return .init(
            phoneNumber: info.phoneNumber,
            codeLength: length,
            deliveryHint: delivery
        )
    }
}
