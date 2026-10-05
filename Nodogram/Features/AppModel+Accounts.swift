//  Several Telegram accounts on one Mac, like Telegram's "Add Account". Each
//  has its own folder (session, files, archive, key); one is active at a time
//  and switching takes a second.

import Foundation
import NodogramDomain

public enum Accounts {
    static let idsKey = "accounts.ids"
    static let activeKey = "accounts.active"
    static let namesKey = "accounts.names"

    /// The original single account keeps the id "default", so existing data
    /// stays where it is.
    public static var ids: [String] {
        let list = UserDefaults.standard.stringArray(forKey: idsKey) ?? []
        return list.isEmpty ? ["default"] : list
    }

    public static var active: String {
        let id = UserDefaults.standard.string(forKey: activeKey) ?? "default"
        return ids.contains(id) ? id : (ids.first ?? "default")
    }

    static var encryptedFlagKey: String { "tdlib.databaseEncrypted.\(active)" }

    public static func name(_ id: String) -> String {
        (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String])?[id] ?? (id == "default" ? "Account" : "New Account")
    }

    static func setName(_ name: String, for id: String) {
        var names = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        names[id] = name
        UserDefaults.standard.set(names, forKey: namesKey)
    }

    static func add() -> String {
        let id = "acct-" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(ids + [id], forKey: idsKey)
        return id
    }

    static func remove(_ id: String) {
        UserDefaults.standard.set(ids.filter { $0 != id }, forKey: idsKey)
    }

    static func activate(_ id: String) {
        UserDefaults.standard.set(id, forKey: activeKey)
    }
}

extension AppModel {

    public var accountIDs: [String] { Accounts.ids }
    public var activeAccountID: String { Accounts.active }

    /// Remembers the signed-in name so the account list can show it.
    func rememberAccountName(_ name: String) {
        guard !name.isEmpty else { return }
        Accounts.setName(name, for: Accounts.active)
        accountsVersion += 1
    }

    public func switchAccount(to id: String) {
        guard id != Accounts.active, Accounts.ids.contains(id) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.closeCurrentAccount()
            Accounts.activate(id)
            self.accountsVersion += 1
            self.accountBeforeAdding = nil
            await self.start()
        }
    }

    /// Starts sign-in for another account, keeping the current one.
    public func addAccount() {
        let previous = Accounts.active
        let id = Accounts.add()
        accountBeforeAdding = previous
        Task { [weak self] in
            guard let self else { return }
            await self.closeCurrentAccount()
            Accounts.activate(id)
            self.accountsVersion += 1
            await self.start()
        }
    }

    /// Abandons a sign-in started with Add Account.
    public func cancelAddingAccount() {
        guard let previous = accountBeforeAdding else { return }
        let abandoned = Accounts.active
        accountBeforeAdding = nil
        Task { [weak self] in
            guard let self else { return }
            await self.closeCurrentAccount()
            Accounts.remove(abandoned)
            Self.removeAccountFolder(abandoned)
            Accounts.activate(previous)
            self.accountsVersion += 1
            await self.start()
        }
    }

    /// After signing out of one of several accounts, move to the next.
    func accountSignedOut() {
        guard Accounts.ids.count > 1 else { return }
        let gone = Accounts.active
        Task { [weak self] in
            guard let self else { return }
            await self.closeCurrentAccount()
            Accounts.remove(gone)
            Self.removeAccountFolder(gone)
            Accounts.activate(Accounts.ids.first ?? "default")
            self.accountsVersion += 1
            await self.start()
        }
    }

    private func closeCurrentAccount() async {
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }
        await gateway?.setOnline(false)
        eventTask?.cancel()
        await gateway?.closeAndWait()
        vaultTask?.cancel(); vaultTask = nil
        storyPollTask?.cancel()
        gateway = nil
        masterKey = nil
        archive = nil
        folders = []
        storyOwners = [:]
        selectedFolderID = nil
        select(nil)
        clearSessionForSwitch()
    }

    static func removeAccountFolder(_ id: String) {
        guard id != "default",
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: support.appendingPathComponent("Nodogram/accounts/\(id)"))
    }
}
