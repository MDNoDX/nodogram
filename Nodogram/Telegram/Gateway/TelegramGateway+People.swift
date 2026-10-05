//  A person's profile, the groups you share, what they wrote there, and the
//  chat actions in the header's ⋯ menu.

import Foundation
import NodogramDomain
import TDLibKit

private typealias Date = Foundation.Date

extension TelegramGateway {

    public func personProfile(_ user: UserID) async -> PersonProfile? {
        guard let u = try? await client.getUser(userId: user.rawValue) else { return nil }
        let full = try? await client.getUserFullInfo(userId: user.rawValue)
        let birthday: String? = full?.birthdate.map { b in
            let months = Calendar(identifier: .gregorian).monthSymbols
            let month = (1...12).contains(b.month) ? months[b.month - 1] : "\(b.month)"
            return b.year > 0 ? "\(b.day) \(month) \(b.year)" : "\(b.day) \(month)"
        }
        let isBot: Bool = { if case .userTypeBot = u.type { return true }; return false }()
        return PersonProfile(
            userID: user, firstName: u.firstName, lastName: u.lastName,
            usernames: u.usernames?.activeUsernames ?? [],
            disabledUsernames: u.usernames?.disabledUsernames ?? [],
            collectibleUsernames: u.usernames?.collectibleUsernames ?? [],
            phoneNumber: u.phoneNumber, bio: full?.bio?.text ?? "", birthday: birthday,
            isContact: u.isContact, isMutualContact: u.isMutualContact,
            isBlocked: full?.blockList != nil, isBot: isBot, isPremium: u.isPremium,
            isVerified: u.verificationStatus?.isVerified ?? false,
            usesUnofficialApp: full?.usesUnofficialApp ?? false,
            groupsInCommonCount: full?.groupInCommonCount ?? 0,
            personalChannelID: (full?.personalChatId ?? 0) != 0 ? ChatID(full!.personalChatId) : nil,
            note: full?.note?.text ?? "")
    }

    /// Every group and channel you share with someone.
    public func groupsInCommon(_ user: UserID) async -> [ChatID] {
        var result: [ChatID] = []
        var offset: Int64 = 0
        for _ in 0..<10 {
            guard let page = try? await client.getGroupsInCommon(limit: 100, offsetChatId: offset, userId: user.rawValue),
                  !page.chatIds.isEmpty else { break }
            result += page.chatIds.map(ChatID.init)
            offset = page.chatIds.last!
            if page.chatIds.count < 100 { break }
        }
        return result
    }

    /// Someone's own messages in one chat, newest first.
    public func messages(from user: UserID, in chat: ChatID, limit: Int = 50) async -> (messages: [NodogramDomain.Message], total: Int) {
        guard let found = try? await client.searchChatMessages(
            chatId: chat.rawValue, filter: nil, fromMessageId: 0, limit: limit, offset: 0, query: "",
            senderId: .messageSenderUser(MessageSenderUser(userId: user.rawValue)), topicId: nil) else { return ([], 0) }
        return (found.messages.map(cache.mapMessage), found.totalCount)
    }

    public func setBlocked(_ user: UserID, _ blocked: Bool) async throws(DomainError) {
        try await run {
            _ = try await self.client.setMessageSenderBlockList(
                blockList: blocked ? .blockListMain : nil,
                senderId: .messageSenderUser(MessageSenderUser(userId: user.rawValue)))
        }
    }

    /// Clears a chat's history — for everyone when `revoke` and allowed.
    public func clearHistory(_ chat: ChatID, revoke: Bool) async throws(DomainError) {
        try await run { _ = try await self.client.deleteChatHistory(chatId: chat.rawValue, removeFromChatList: false, revoke: revoke) }
    }

    /// Deletes a private chat (history and the chat itself), or leaves a group.
    public func deleteChat(_ chat: ChatID, revoke: Bool) async throws(DomainError) {
        try await run {
            if chat.rawValue > 0 {
                _ = try await self.client.deleteChatHistory(chatId: chat.rawValue, removeFromChatList: true, revoke: revoke)
            } else {
                _ = try await self.client.leaveChat(chatId: chat.rawValue)
            }
        }
    }

    /// 0 turns auto-delete off; otherwise seconds (86400, 604800, 2678400…).
    public func setAutoDelete(_ chat: ChatID, seconds: Int) async throws(DomainError) {
        try await run { _ = try await self.client.setChatMessageAutoDeleteTime(chatId: chat.rawValue, messageAutoDeleteTime: seconds) }
    }

    /// Mutes for a number of seconds (0 unmutes).
    public func mute(_ chat: ChatID, for seconds: Int) async throws(DomainError) {
        guard let current = cache.notificationSettings(chatId: chat.rawValue) else { return }
        let updated = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: seconds, muteStories: current.muteStories, showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster, soundId: current.soundId, storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false, useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview, useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound, useDefaultStorySound: current.useDefaultStorySound)
        try await run { _ = try await self.client.setChatNotificationSettings(chatId: chat.rawValue, notificationSettings: updated) }
    }

    /// Saves or renames a contact, without sharing your number.
    public func saveContact(_ user: UserID, firstName: String, lastName: String, phone: String) async throws(DomainError) {
        try await run {
            _ = try await self.client.addContact(
                contact: ImportedContact(firstName: firstName, lastName: lastName, note: nil, phoneNumber: phone),
                sharePhoneNumber: false, userId: user.rawValue)
        }
    }

    public func createGroup(title: String, with users: [UserID]) async throws(DomainError) -> ChatID {
        try await run {
            let created = try await self.client.createNewBasicGroupChat(
                messageAutoDeleteTime: 0, title: title, userIds: users.map(\.rawValue))
            return ChatID(created.chatId)
        }
    }

    /// People who have you in their contacts while you have them in yours —
    /// the only "who saved me" Telegram reveals.
    public func mutualContacts() async -> [UserID] {
        guard let contacts = try? await client.getContacts() else { return [] }
        var mutual: [UserID] = []
        for id in contacts.userIds {
            var user = cache.user(id)
            if user == nil { user = try? await client.getUser(userId: id) }
            if user?.isMutualContact == true { mutual.append(UserID(id)) }
        }
        return mutual
    }

    public func chatDescription(_ chat: ChatID) async -> String {
        let identity = cache.groupIdentity(chatId: chat.rawValue)
        if let supergroup = identity.supergroup {
            return (try? await client.getSupergroupFullInfo(supergroupId: supergroup))?.description ?? ""
        }
        if let basic = identity.basic {
            return (try? await client.getBasicGroupFullInfo(basicGroupId: basic))?.description ?? ""
        }
        return ""
    }
}
