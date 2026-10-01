//  Symmetric keys held in the macOS Keychain.
//
//  Generated once with the system CSPRNG, stored as a generic password marked
//  `ThisDeviceOnly` so it never syncs to iCloud, and never written anywhere
//  else. See Documentation/SECURITY_MODEL.md §3.

import CryptoKit
import Foundation
import Security

public enum KeychainKey {

    public enum Failure: Error, Equatable {
        case keychain(OSStatus)
        case corruptKey
    }

    /// Loads the key for `account`, creating it on first use.
    public static func loadOrCreate(service: String, account: String) throws -> SymmetricKey {
        if let existing = try load(service: service, account: account) { return existing }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem, let raced = try load(service: service, account: account) {
            return raced
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        return key
    }

    /// Deleting the key makes everything encrypted with it unreadable — the
    /// strongest form of erase available, since it does not depend on the
    /// file system actually discarding the old bytes.
    public static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func load(service: String, account: String) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw Failure.corruptKey }
        return SymmetricKey(data: data)
    }
}
