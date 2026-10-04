//  The master key, kept in a file only this macOS user can read.
//
//  Why not the Keychain: macOS ties Keychain approval to the app's code
//  signature. Builds without an Apple Developer Team ID get a new identity
//  every build, so the Keychain asked for the login password on every update.
//  Telegram Desktop keeps its local key the same way — in its own data folder,
//  protected by the user account and FileVault. Documentation/DECISIONS.md D16.

import CryptoKit
import Foundation

public enum LocalKeyStore {

    public static func fileURL(directory: URL) -> URL {
        directory.appendingPathComponent("master.key")
    }

    public static func load(directory: URL) -> SymmetricKey? {
        guard let data = try? Data(contentsOf: fileURL(directory: directory)), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// Writes atomically with owner-only permissions and keeps it out of
    /// Time Machine and iCloud backups.
    public static func save(_ key: SymmetricKey, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = fileURL(directory: directory)
        let data = key.withUnsafeBytes { Data($0) }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    public static func generate(directory: URL) throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        try save(key, directory: directory)
        return key
    }
}
