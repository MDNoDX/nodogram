//  People: their profile, the groups you share, what they wrote there, and
//  their name and username history as this Mac has seen it.

import Foundation
import NodogramDomain
import NodogramTelegram

/// Name and username history, kept on this Mac. Telegram does not keep old
/// names for others to see; Nodogram records every change it observes —
/// including ones made while it was closed, noticed when it next syncs.
@MainActor
final class UserHistoryStore {
    private(set) var history: [Int64: [UserIdentity]] = [:]
    private var dirty = false
    private var saveTask: Task<Void, Never>?

    nonisolated static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Nodogram/user-history.json")
    }()

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? decoder.decode([Int64: [UserIdentity]].self, from: data) {
            history = decoded
        }
    }

    /// Records the identity if it differs from the last one seen.
    func note(_ user: UserID, _ identity: UserIdentity) {
        var entries = history[user.rawValue] ?? []
        if let last = entries.last, last.sameAs(identity) { return }
        if identity.name.isEmpty && identity.usernames.isEmpty { return }
        entries.append(identity)
        history[user.rawValue] = entries
        scheduleSave()
    }

    func entries(for user: UserID) -> [UserIdentity] { history[user.rawValue] ?? [] }

    private func scheduleSave() {
        dirty = true
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            let snapshot = self.history
            self.saveTask = nil
            self.dirty = false
            Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .secondsSince1970
                guard let data = try? encoder.encode(snapshot) else { return }
                try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: Self.fileURL, options: .atomic)
            }
        }
    }
}

/// What the profile panel shows about someone, gathered on open.
public struct PersonActivity: Sendable {
    public var profile: PersonProfile?
    public var commonGroups: [ChatID] = []
    /// Their latest messages in shared groups, newest first.
    public var groupMessages: [Message] = []
    public var groupMessageCounts: [ChatID: Int] = [:]
    public var identities: [UserIdentity] = []
    public var deletedCount = 0
    public var typingCount = 0
    public var abandonedTypingCount = 0
    public var storyViews = 0
    public var isLoading = true
}

extension AppModel {

    func noteIdentity(_ user: UserID, _ identity: UserIdentity) {
        userHistory.note(user, identity)
    }

    public func identityHistory(_ user: UserID) -> [UserIdentity] { userHistory.entries(for: user) }

    // MARK: - Profile panel

    public func toggleInfoPanel() {
        infoPanelVisible.toggle()
    }

    /// Everything about one person, in steps so the panel fills in quickly.
    public func loadActivity(for user: UserID, update: @escaping @MainActor (PersonActivity) -> Void) async {
        guard let gateway else { return }
        var activity = PersonActivity()
        activity.identities = identityHistory(user)
        activity.typingCount = typingLog.filter { $0.userID == user.rawValue }.count
        activity.abandonedTypingCount = typingLog.filter { $0.userID == user.rawValue && $0.outcome == .abandoned }.count
        activity.storyViews = storyViewers.filter { $0.userID == user.rawValue }.count
        if let archive {
            activity.deletedCount = await archive.recentlyDeleted(limit: 2000)
                .filter { $0.senderID == user || ($0.chatID.rawValue == user.rawValue && !$0.isOutgoing) }.count
        }
        update(activity)

        activity.profile = await gateway.personProfile(user)
        update(activity)

        activity.commonGroups = await gateway.groupsInCommon(user)
        update(activity)

        // Their messages in each shared group, a page per group, merged.
        var all: [Message] = []
        for chat in activity.commonGroups.prefix(25) {
            let page = await gateway.messages(from: user, in: chat, limit: 20)
            activity.groupMessageCounts[chat] = page.total
            all += page.messages
        }
        activity.groupMessages = all.sorted { $0.date > $1.date }
        activity.isLoading = false
        update(activity)
    }

    // MARK: - Header ⋯ actions

    public func mute(_ chat: ChatID, for seconds: Int) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                try await gateway.mute(chat, for: seconds)
                self?.showToast(seconds == 0 ? "Unmuted" : "Muted")
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func setAutoDelete(_ chat: ChatID, seconds: Int) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                try await gateway.setAutoDelete(chat, seconds: seconds)
                self?.showToast(seconds == 0 ? "Auto-delete off" : "Auto-delete on")
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func setBlocked(_ user: UserID, _ blocked: Bool) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                try await gateway.setBlocked(user, blocked)
                self?.showToast(blocked ? "Blocked" : "Unblocked")
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func clearHistory(_ chat: ChatID, forEveryone: Bool) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                try await gateway.clearHistory(chat, revoke: forEveryone)
                self?.showToast("History cleared")
                if self?.selectedChatID == chat { self?.reloadLatest() }
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func deleteChat(_ chat: ChatID, forEveryone: Bool) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                try await gateway.deleteChat(chat, revoke: forEveryone)
                if self?.selectedChatID == chat { self?.select(nil) }
                self?.showToast("Chat deleted")
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func saveContact(_ user: UserID, firstName: String, lastName: String, phone: String) async -> String? {
        do { try await gateway?.saveContact(user, firstName: firstName, lastName: lastName, phone: phone); return nil }
        catch { return error.userFacingDescription }
    }

    public func createGroup(title: String, with users: [UserID]) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                let chat = try await gateway.createGroup(title: title, with: users)
                self?.selectedDestination = .allChats
                self?.select(chat)
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func mutualContacts() async -> [UserID] { await gateway?.mutualContacts() ?? [] }

    public func chatDescription(_ chat: ChatID) async -> String { await gateway?.chatDescription(chat) ?? "" }

    // MARK: - Per-chat wallpaper

    public func wallpaper(for chat: ChatID) -> Int? {
        (UserDefaults.standard.dictionary(forKey: "chat.wallpapers") as? [String: Int])?[String(chat.rawValue)]
    }

    public func setWallpaper(_ index: Int?, for chat: ChatID) {
        var map = (UserDefaults.standard.dictionary(forKey: "chat.wallpapers") as? [String: Int]) ?? [:]
        map[String(chat.rawValue)] = index
        UserDefaults.standard.set(map, forKey: "chat.wallpapers")
        chatWallpaperVersion += 1
    }
}

extension AppModel {
    public func gatewayProfile(_ user: UserID) async -> PersonProfile? { await gateway?.personProfile(user) }
}
