//  Settings that round-trip through Telegram, plus the user's own footprint
//  (groups, their messages, members of groups they run).

import Foundation
import NodogramDomain
import NodogramTelegram

extension AppModel {

    // MARK: - Profile

    public func loadProfile() async -> ProfileInfo? { try? await gateway?.profile() }

    /// Saves only what changed. Returns an error message, or nil on success.
    public func saveProfile(old: ProfileInfo, new: ProfileInfo) async -> String? {
        guard let gateway else { return "Not connected." }
        do {
            if old.firstName != new.firstName || old.lastName != new.lastName {
                try await gateway.setName(first: new.firstName, last: new.lastName)
            }
            if old.bio != new.bio { try await gateway.setBio(new.bio) }
            if old.username != new.username { try await gateway.setUsername(new.username) }
            return nil
        } catch {
            return error.userFacingDescription
        }
    }

    // MARK: - Sessions

    public func loadSessions() async -> [SessionInfo] { (try? await gateway?.sessions()) ?? [] }

    public func terminate(_ session: SessionInfo) async -> String? {
        do { try await gateway?.terminateSession(session.id); return nil }
        catch { return error.userFacingDescription }
    }

    public func terminateOtherSessions() async -> String? {
        do { try await gateway?.terminateOtherSessions(); return nil }
        catch { return error.userFacingDescription }
    }

    // MARK: - Privacy

    public func privacyRule(_ key: PrivacyKey) async -> PrivacyRule? { try? await gateway?.privacy(key) }

    public func setPrivacy(_ key: PrivacyKey, _ rule: PrivacyRule) async -> String? {
        do { try await gateway?.setPrivacy(key, rule); return nil }
        catch { return error.userFacingDescription }
    }

    // MARK: - Notification defaults

    public func scopeNotifications(_ scope: ScopeNotifications.Scope) async -> ScopeNotifications? {
        try? await gateway?.scopeNotifications(scope)
    }

    public func setScopeNotifications(_ scope: ScopeNotifications.Scope, _ value: ScopeNotifications) async {
        do { try await gateway?.setScopeNotifications(scope, value) }
        catch { showToast(error.userFacingDescription) }
    }

    // MARK: - Storage

    public func storageUsage() async -> StorageUsage? { try? await gateway?.storageUsage() }

    public func clearCache() async {
        do { try await gateway?.clearCache(); showToast("Cache cleared") }
        catch { showToast(error.userFacingDescription) }
    }

    // MARK: - My activity

    public func myGroups() -> [GroupSummary] { gateway?.myGroups() ?? [] }

    public func myMessages(in chat: ChatID, from: MessageID? = nil) async -> (messages: [Message], total: Int, next: MessageID?) {
        (try? await gateway?.myMessages(in: chat, from: from)) ?? ([], 0, nil)
    }

    /// Deletes every message the user sent in a chat. Reports progress.
    public func deleteAllMyMessages(in chat: ChatID, progress: @escaping @MainActor (Int, Int) -> Void) async -> String? {
        guard let gateway else { return "Not connected." }
        do {
            let count = try await gateway.deleteAllMyMessages(in: chat) { done, total in
                Task { @MainActor in progress(done, total) }
            }
            showToast("Deleted \(count) of your messages")
            if chat == selectedChatID { reloadLatest() }
            return nil
        } catch {
            return error.userFacingDescription
        }
    }

    public func leave(_ chat: ChatID) async -> String? {
        do {
            try await gateway?.leave(chat)
            if selectedChatID == chat { select(nil) }
            return nil
        } catch { return error.userFacingDescription }
    }

    public func members(of chat: ChatID, query: String) async -> (members: [MemberInfo], total: Int) {
        (try? await gateway?.members(of: chat, query: query)) ?? ([], 0)
    }

    public func remove(_ member: MemberInfo, from chat: ChatID, ban: Bool) async -> String? {
        do { try await gateway?.removeMember(member.userID, from: chat, ban: ban); return nil }
        catch { return error.userFacingDescription }
    }

    public func setProfilePhoto(path: String) async -> String? {
        do { try await gateway?.setProfilePhoto(path: path); return nil }
        catch { return error.userFacingDescription }
    }

    public func clearSavedGIFs() async -> String? {
        do { let n = try await gateway?.clearSavedGIFs() ?? 0; showToast("Cleared \(n) saved GIFs"); return nil }
        catch { return error.userFacingDescription }
    }

    public func clearMyStories() async -> String? {
        do { let n = try await gateway?.clearMyStories() ?? 0; showToast(n == 0 ? "No active stories" : "Deleted \(n) stories"); return nil }
        catch { return error.userFacingDescription }
    }
}
