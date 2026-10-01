//  Telegram API credentials.
//
//  Loaded at runtime from the app bundle's Info.plist, which is populated from
//  Config/Secrets.xcconfig — a git-ignored file. Credentials are never
//  compiled into source. See Documentation/SECURITY_MODEL.md §7.

import Foundation
import NodogramDomain

public struct TelegramCredentials: Sendable {
    public let apiID: Int
    public let apiHash: String

    public init(apiID: Int, apiHash: String) {
        self.apiID = apiID
        self.apiHash = apiHash
    }

    /// Reads credentials from the bundle, or explains precisely what is missing.
    ///
    /// The error text names the file and the keys, because "missing
    /// credentials" alone would leave the user guessing.
    public static func fromBundle(_ bundle: Bundle = .main) -> Result<TelegramCredentials, DomainError> {
        let rawID = bundle.object(forInfoDictionaryKey: "TelegramAPIID") as? String
        let rawHash = bundle.object(forInfoDictionaryKey: "TelegramAPIHash") as? String

        let trimmedID = rawID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedHash = rawHash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedID.isEmpty || trimmedHash.isEmpty {
            return .failure(.missingCredentials(detail: """
                TELEGRAM_API_ID and TELEGRAM_API_HASH are not set.

                1. cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
                2. Fill in both values from https://my.telegram.org
                3. Rebuild with Tools/build-app.sh
                """))
        }

        guard let apiID = Int(trimmedID) else {
            return .failure(.missingCredentials(
                detail: "TELEGRAM_API_ID must be a number, but was \"\(trimmedID)\"."))
        }

        // A real api_hash is a 32-character hex string. Catching this here beats
        // a confusing authentication failure later.
        guard trimmedHash.count == 32 else {
            return .failure(.missingCredentials(
                detail: "TELEGRAM_API_HASH should be 32 characters, but was \(trimmedHash.count)."))
        }

        return .success(TelegramCredentials(apiID: apiID, apiHash: trimmedHash))
    }
}
