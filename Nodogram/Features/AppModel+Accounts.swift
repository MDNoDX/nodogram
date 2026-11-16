//  Several Telegram accounts on one Mac, like Telegram's "Add Account". Each
//  has its own folder (session, files, archive, key); one is active at a time
//  and switching takes a second.

import Foundation
import NodogramDomain

public enum Accounts {
    static let idsKey = "accounts.ids"
    static let activeKey = "accounts.active"
    static let namesKey = "accounts.names"
    static let userIDsKey = "accounts.userIDs"

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
        forgetUserID(id)
    }

    static func activate(_ id: String) {
        UserDefaults.standard.set(id, forKey: activeKey)
    }

    // ── Telegram identity per account (to catch the same number added twice) ──

    static func userID(_ id: String) -> Int64? {
        (UserDefaults.standard.dictionary(forKey: userIDsKey) as? [String: NSNumber])?[id]?.int64Value
    }

    static func setUserID(_ uid: Int64, for id: String) {
        var map = (UserDefaults.standard.dictionary(forKey: userIDsKey) as? [String: NSNumber]) ?? [:]
        map[id] = NSNumber(value: uid)
        UserDefaults.standard.set(map, forKey: userIDsKey)
    }

    static func forgetUserID(_ id: String) {
        guard var map = UserDefaults.standard.dictionary(forKey: userIDsKey) as? [String: NSNumber] else { return }
        map[id] = nil
        UserDefaults.standard.set(map, forKey: userIDsKey)
    }

    /// An account other than `except` that is already signed into this same
    /// Telegram user, if any — i.e. the same number added twice.
    static func twin(ofUserID uid: Int64, except: String) -> String? {
        let map = (UserDefaults.standard.dictionary(forKey: userIDsKey) as? [String: NSNumber]) ?? [:]
        return ids.first { $0 != except && map[$0]?.int64Value == uid }
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

    /// After signing out of one of several accounts, move to another — and
    /// prefer one that is already signed in, so we land on a real account
    /// window instead of the phone-number screen.
    func accountSignedOut() {
        guard Accounts.ids.count > 1 else { return }
        let gone = Accounts.active
        let remaining = Accounts.ids.filter { $0 != gone }
        let next = remaining.first { Accounts.userID($0) != nil } ?? remaining.first ?? "default"
        Task { [weak self] in
            guard let self else { return }
            await self.closeCurrentAccount()
            Accounts.remove(gone)
            Self.removeAccountFolder(gone)
            Accounts.activate(next)
            self.accountBeforeAdding = nil
            self.accountsVersion += 1
            await self.start()
        }
    }

    /// Called once an account reaches `ready` and its Telegram user id is known.
    /// Records that id, and if another account slot is already signed into the
    /// very same Telegram user (the same number added twice), collapses the two
    /// into one. Returns `true` when THIS slot was the duplicate and is being
    /// torn down (so the caller should stop setting up the old session).
    @discardableResult
    func reconcileAccountIdentity(userID uid: Int64) -> Bool {
        let active = Accounts.active
        guard let twin = Accounts.twin(ofUserID: uid, except: active) else {
            Accounts.setUserID(uid, for: active)
            return false
        }
        // Two slots hold the same account. Keep "default" when it is one of them
        // (its folder is the original data); otherwise keep the one we are on.
        let keep = (twin == "default") ? twin : active
        let drop = (keep == active) ? twin : active
        Accounts.setUserID(uid, for: keep)

        if drop == active {
            // We are the duplicate → hand off to the twin and remove ourselves.
            Task { [weak self] in
                guard let self else { return }
                await self.closeCurrentAccount()
                Accounts.remove(drop)
                Self.removeAccountFolder(drop)
                Accounts.activate(keep)
                self.accountBeforeAdding = nil
                self.accountsVersion += 1
                await self.start()
            }
            return true
        } else {
            // The other slot is the duplicate → just forget it; we stay.
            Accounts.remove(drop)
            Self.removeAccountFolder(drop)
            accountsVersion += 1
            return false
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
