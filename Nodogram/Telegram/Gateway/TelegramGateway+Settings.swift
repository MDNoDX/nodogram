//  Folders and account settings: profile, sessions, privacy, notification
//  defaults and storage. Everything here round-trips through Telegram, so it
//  stays in sync with the user's other devices.

import Foundation
import NodogramDomain
import TDLibKit

private typealias Date = Foundation.Date

extension TelegramGateway {

    // MARK: - Folders

    public func chatFolder(_ id: Int) async throws(DomainError) -> ChatFolderDraft {
        try await run { Self.draft(try await self.client.getChatFolder(chatFolderId: id)) }
    }

    @discardableResult
    public func createFolder(_ draft: ChatFolderDraft) async throws(DomainError) -> Int {
        try await run { try await self.client.createChatFolder(folder: Self.tdFolder(draft)).id }
    }

    public func editFolder(_ id: Int, _ draft: ChatFolderDraft) async throws(DomainError) {
        try await run { _ = try await self.client.editChatFolder(chatFolderId: id, folder: Self.tdFolder(draft)) }
    }

    public func deleteFolder(_ id: Int) async throws(DomainError) {
        try await run { _ = try await self.client.deleteChatFolder(chatFolderId: id, leaveChatIds: []) }
    }

    /// `mainPosition` is where "All Chats" sits; Telegram requires 0 unless
    /// the account is Premium.
    public func reorderFolders(_ ids: [Int], mainPosition: Int = 0) async throws(DomainError) {
        try await run {
            _ = try await self.client.reorderChatFolders(chatFolderIds: ids, mainChatListPosition: mainPosition)
        }
    }

    public func recommendedFolders() async -> [RecommendedFolder] {
        guard let result = try? await client.getRecommendedChatFolders() else { return [] }
        return result.chatFolders.map { RecommendedFolder(draft: Self.draft($0.folder), description: $0.description) }
    }

    static func draft(_ f: ChatFolder) -> ChatFolderDraft {
        ChatFolderDraft(
            title: f.name.text.text, iconName: f.icon?.name ?? "", colorID: f.colorId,
            includeContacts: f.includeContacts, includeNonContacts: f.includeNonContacts,
            includeGroups: f.includeGroups, includeChannels: f.includeChannels, includeBots: f.includeBots,
            excludeMuted: f.excludeMuted, excludeRead: f.excludeRead, excludeArchived: f.excludeArchived,
            includedChatIDs: f.includedChatIds.map(ChatID.init), excludedChatIDs: f.excludedChatIds.map(ChatID.init),
            pinnedChatIDs: f.pinnedChatIds.map(ChatID.init))
    }

    static func tdFolder(_ d: ChatFolderDraft) -> ChatFolder {
        ChatFolder(
            colorId: d.colorID, excludeArchived: d.excludeArchived, excludeMuted: d.excludeMuted,
            excludeRead: d.excludeRead, excludedChatIds: d.excludedChatIDs.map(\.rawValue),
            icon: d.iconName.isEmpty ? nil : ChatFolderIcon(name: d.iconName),
            includeBots: d.includeBots, includeChannels: d.includeChannels, includeContacts: d.includeContacts,
            includeGroups: d.includeGroups, includeNonContacts: d.includeNonContacts,
            includedChatIds: d.includedChatIDs.map(\.rawValue), isShareable: false,
            name: ChatFolderName(animateCustomEmoji: false, text: FormattedText(entities: [], text: d.title)),
            pinnedChatIds: d.pinnedChatIDs.map(\.rawValue))
    }

    // MARK: - Profile

    public func profile() async throws(DomainError) -> ProfileInfo {
        try await run {
            let me = try await self.client.getMe()
            let full = try? await self.client.getUserFullInfo(userId: me.id)
            return ProfileInfo(
                userID: UserID(me.id), firstName: me.firstName, lastName: me.lastName,
                username: me.usernames?.editableUsername ?? "", phoneNumber: me.phoneNumber,
                bio: full?.bio?.text ?? "", isPremium: me.isPremium)
        }
    }

    public func setName(first: String, last: String) async throws(DomainError) {
        try await run { _ = try await self.client.setName(firstName: first, lastName: last) }
    }

    public func setBio(_ bio: String) async throws(DomainError) {
        try await run { _ = try await self.client.setBio(bio: bio) }
    }

    public func setUsername(_ username: String) async throws(DomainError) {
        try await run { _ = try await self.client.setUsername(username: username) }
    }

    // MARK: - Sessions

    public func sessions() async throws(DomainError) -> [SessionInfo] {
        try await run {
            try await self.client.getActiveSessions().sessions.map { s in
                SessionInfo(
                    id: s.id.rawValue, isCurrent: s.isCurrent, applicationName: s.applicationName,
                    applicationVersion: s.applicationVersion, deviceModel: s.deviceModel, platform: s.platform,
                    systemVersion: s.systemVersion, location: s.location, ipAddress: s.ipAddress,
                    lastActive: Date(timeIntervalSince1970: TimeInterval(s.lastActiveDate)),
                    isOfficial: s.isOfficialApplication, symbol: Self.symbol(for: s.deviceType))
            }
        }
    }

    public func terminateSession(_ id: Int64) async throws(DomainError) {
        try await run { _ = try await self.client.terminateSession(sessionId: TdInt64(id)) }
    }

    public func terminateOtherSessions() async throws(DomainError) {
        try await run { _ = try await self.client.terminateAllOtherSessions() }
    }

    private static func symbol(for type: SessionDeviceType) -> String {
        switch type {
        case .sessionDeviceTypeIphone: return "iphone"
        case .sessionDeviceTypeIpad: return "ipad"
        case .sessionDeviceTypeMac: return "laptopcomputer"
        case .sessionDeviceTypeAndroid: return "candybarphone"
        case .sessionDeviceTypeWindows, .sessionDeviceTypeLinux, .sessionDeviceTypeUbuntu: return "desktopcomputer"
        case .sessionDeviceTypeChrome, .sessionDeviceTypeSafari, .sessionDeviceTypeFirefox,
             .sessionDeviceTypeEdge, .sessionDeviceTypeOpera, .sessionDeviceTypeBrave, .sessionDeviceTypeVivaldi:
            return "globe"
        default: return "questionmark.app"
        }
    }

    // MARK: - Privacy

    public func privacy(_ key: PrivacyKey) async throws(DomainError) -> PrivacyRule {
        try await run {
            let rules = try await self.client.getUserPrivacySettingRules(setting: Self.setting(key)).rules
            var rule = PrivacyRule(audience: .nobody)
            for r in rules {
                switch r {
                case .userPrivacySettingRuleAllowAll: rule.audience = .everybody
                case .userPrivacySettingRuleAllowContacts: if rule.audience == .nobody { rule.audience = .contacts }
                case .userPrivacySettingRuleAllowUsers(let u): rule.allowUserIDs += u.userIds
                case .userPrivacySettingRuleAllowChatMembers(let c): rule.allowChatIDs += c.chatIds
                case .userPrivacySettingRuleRestrictUsers(let u): rule.restrictUserIDs += u.userIds
                case .userPrivacySettingRuleRestrictChatMembers(let c): rule.restrictChatIDs += c.chatIds
                default: break
                }
            }
            return rule
        }
    }

    public func setPrivacy(_ key: PrivacyKey, _ rule: PrivacyRule) async throws(DomainError) {
        // Exceptions first, then the base audience, as Telegram's apps send them.
        var rules: [UserPrivacySettingRule] = []
        if !rule.restrictUserIDs.isEmpty {
            rules.append(.userPrivacySettingRuleRestrictUsers(.init(userIds: rule.restrictUserIDs)))
        }
        if !rule.restrictChatIDs.isEmpty {
            rules.append(.userPrivacySettingRuleRestrictChatMembers(.init(chatIds: rule.restrictChatIDs)))
        }
        if !rule.allowUserIDs.isEmpty {
            rules.append(.userPrivacySettingRuleAllowUsers(.init(userIds: rule.allowUserIDs)))
        }
        if !rule.allowChatIDs.isEmpty {
            rules.append(.userPrivacySettingRuleAllowChatMembers(.init(chatIds: rule.allowChatIDs)))
        }
        switch rule.audience {
        case .everybody: rules.append(.userPrivacySettingRuleAllowAll)
        case .contacts: rules.append(.userPrivacySettingRuleAllowContacts); rules.append(.userPrivacySettingRuleRestrictAll)
        case .nobody: rules.append(.userPrivacySettingRuleRestrictAll)
        }
        let final = rules
        try await run {
            _ = try await self.client.setUserPrivacySettingRules(
                rules: UserPrivacySettingRules(rules: final), setting: Self.setting(key))
        }
    }

    private static func setting(_ key: PrivacyKey) -> UserPrivacySetting {
        switch key {
        case .phoneNumber: return .userPrivacySettingShowPhoneNumber
        case .lastSeen: return .userPrivacySettingShowStatus
        case .profilePhoto: return .userPrivacySettingShowProfilePhoto
        case .bio: return .userPrivacySettingShowBio
        case .birthday: return .userPrivacySettingShowBirthdate
        case .forwards: return .userPrivacySettingShowLinkInForwardedMessages
        case .calls: return .userPrivacySettingAllowCalls
        case .groupInvites: return .userPrivacySettingAllowChatInvites
        case .voiceMessages: return .userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages
        }
    }

    // MARK: - Notification defaults

    public func scopeNotifications(_ scope: ScopeNotifications.Scope) async throws(DomainError) -> ScopeNotifications {
        try await run {
            let s = try await self.client.getScopeNotificationSettings(scope: Self.tdScope(scope))
            return ScopeNotifications(isMuted: s.muteFor > 0, showPreview: s.showPreview)
        }
    }

    public func setScopeNotifications(_ scope: ScopeNotifications.Scope, _ value: ScopeNotifications) async throws(DomainError) {
        try await run {
            let current = try await self.client.getScopeNotificationSettings(scope: Self.tdScope(scope))
            let updated = ScopeNotificationSettings(
                disableMentionNotifications: current.disableMentionNotifications,
                disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
                muteFor: value.isMuted ? 366 * 86_400 : 0,
                muteStories: current.muteStories, showPreview: value.showPreview,
                showStoryPoster: current.showStoryPoster, soundId: current.soundId,
                storySoundId: current.storySoundId, useDefaultMuteStories: current.useDefaultMuteStories)
            _ = try await self.client.setScopeNotificationSettings(notificationSettings: updated, scope: Self.tdScope(scope))
        }
    }

    private static func tdScope(_ scope: ScopeNotifications.Scope) -> NotificationSettingsScope {
        switch scope {
        case .privateChats: return .notificationSettingsScopePrivateChats
        case .groups: return .notificationSettingsScopeGroupChats
        case .channels: return .notificationSettingsScopeChannelChats
        }
    }

    // MARK: - Storage

    public func storageUsage() async throws(DomainError) -> StorageUsage {
        try await run {
            let s = try await self.client.getStorageStatisticsFast()
            return StorageUsage(filesSize: s.filesSize, fileCount: s.fileCount, databaseSize: s.databaseSize)
        }
    }

    /// Deletes cached media files. Messages are untouched; files download again
    /// when needed.
    public func clearCache() async throws(DomainError) {
        try await run {
            _ = try await self.client.optimizeStorage(
                chatIds: [], chatLimit: 0, count: 0, excludeChatIds: [], fileTypes: [],
                immunityDelay: 0, returnDeletedFileStatistics: false, size: 0, ttl: 0)
        }
    }
}

extension TelegramGateway {
    /// Sets a new profile photo from a file on this Mac.
    public func setProfilePhoto(path: String) async throws(DomainError) {
        try await run {
            _ = try await self.client.setProfilePhoto(
                isPublic: false,
                photo: .inputChatPhotoStatic(InputChatPhotoStatic(photo: .inputFileLocal(InputFileLocal(path: path)))))
        }
    }
}
