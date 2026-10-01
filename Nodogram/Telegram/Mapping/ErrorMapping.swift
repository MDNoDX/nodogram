//  Translates TDLib errors into DomainError.
//
//  This is the only place TDLib error codes are interpreted, so the rest of the
//  app never sees a raw protocol error (Documentation/ARCHITECTURE.md §2).

import Foundation
import NodogramDomain
import TDLibKit

enum ErrorMapping {
    /// Maps a thrown TDLib error to a domain error.
    static func map(_ error: any Swift.Error) -> DomainError {
        // `TDLibKit.Error` is a concrete struct carrying TDLib's code/message.
        guard let tdError = error as? TDLibKit.Error else {
            return .protocolFailure(code: -1, message: String(describing: error))
        }
        return map(code: tdError.code, message: tdError.message)
    }

    static func map(code: Int, message: String) -> DomainError {
        // Verified behaviour: TDLib returns exactly this before
        // setTdlibParameters. See Documentation/ARCHITECTURE.md §1.2.
        if code == 400, message.contains("Initialization parameters are needed") {
            return .notInitialized
        }

        switch code {
        case 401:
            return .notAuthorized
        case 420:
            // FLOOD_WAIT_<seconds>
            let seconds = message
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap(Int.init)
                .first
            return .rateLimited(retryAfter: TimeInterval(seconds ?? 60))
        case 400:
            if message.contains("PHONE_NUMBER_INVALID") { return .invalidPhoneNumber }
            if message.contains("PHONE_CODE_INVALID") || message.contains("PHONE_CODE_EXPIRED") {
                return .invalidCode
            }
            if message.contains("PASSWORD_HASH_INVALID") { return .invalidPassword }
            return .protocolFailure(code: code, message: message)
        default:
            return .protocolFailure(code: code, message: message)
        }
    }
}
