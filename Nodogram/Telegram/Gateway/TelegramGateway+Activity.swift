//  The user's own footprint: their messages, groups and channels, members of
//  groups they run, and who viewed their stories.

import Foundation
import NodogramDomain
import TDLibKit

private typealias Date = Foundation.Date

extension TelegramGateway {

    /// A user's display name from what TDLib already sent, if known.
    public func userName(_ id: UserID) -> String? {
        cache.user(id.rawValue).map(ChatCache.displayName)
    }

    // MARK: - Groups

    public func myGroups() -> [GroupSummary] {
        cache.groupSummaries().sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func leave(_ chat: ChatID) async throws(DomainError) {
        try await run { _ = try await self.client.leaveChat(chatId: chat.rawValue) }
    }

    // MARK: - My messages

    /// One page of the user's own messages in a chat, newest first.
    public func myMessages(in chat: ChatID, from: MessageID? = nil, limit: Int = 100) async throws(DomainError)
        -> (messages: [NodogramDomain.Message], total: Int, next: MessageID?) {
        let me = try await myUserID()
        return try await run {
            let found = try await self.client.searchChatMessages(
                chatId: chat.rawValue, filter: nil, fromMessageId: from?.rawValue ?? 0, limit: limit,
                offset: 0, query: "", senderId: .messageSenderUser(MessageSenderUser(userId: me.rawValue)),
                topicId: nil)
            return (found.messages.map(self.cache.mapMessage), found.totalCount,
                    found.nextFromMessageId == 0 ? nil : MessageID(found.nextFromMessageId))
        }
    }

    /// Deletes every message the user sent in a chat, for everyone, page by
    /// page. Reports progress as (deleted, total). Messages Telegram will not
    /// let the user delete for everyone are left alone.
    public func deleteAllMyMessages(in chat: ChatID,
                                    progress: @Sendable @escaping (Int, Int) -> Void) async throws(DomainError) -> Int {
        var deleted = 0
        var total = 0
        var rounds = 0
        while rounds < 500 {
            rounds += 1
            let page = try await myMessages(in: chat, from: nil, limit: 100)
            if total == 0 { total = page.total }
            let ids = page.messages.map(\.id.rawValue)
            guard !ids.isEmpty else { break }
            try await run { _ = try await self.client.deleteMessages(chatId: chat.rawValue, messageIds: ids, revoke: true) }
            deleted += ids.count
            progress(deleted, max(total, deleted))
            // Stay well inside Telegram's flood limits.
            try? await Task.sleep(for: .milliseconds(400))
            if page.next == nil, ids.count < 100 { break }
        }
        return deleted
    }

    // MARK: - Members

    public func members(of chat: ChatID, query: String = "", offset: Int = 0, limit: Int = 200) async throws(DomainError)
        -> (members: [MemberInfo], total: Int) {
        let identity = cache.groupIdentity(chatId: chat.rawValue)
        return try await run {
            let raw: [ChatMember]
            let total: Int
            if let supergroup = identity.supergroup {
                let filter: SupergroupMembersFilter = query.isEmpty
                    ? .supergroupMembersFilterRecent
                    : .supergroupMembersFilterSearch(SupergroupMembersFilterSearch(query: query))
                let result = try await self.client.getSupergroupMembers(
                    filter: filter, limit: limit, offset: offset, supergroupId: supergroup)
                raw = result.members; total = result.totalCount
            } else if let basic = identity.basic {
                raw = try await self.client.getBasicGroupFullInfo(basicGroupId: basic).members
                total = raw.count
            } else {
                raw = []; total = 0
            }
            var members: [MemberInfo] = []
            for member in raw {
                guard case .messageSenderUser(let sender) = member.memberId else { continue }
                var user = self.cache.user(sender.userId)
                if user == nil { user = try? await self.client.getUser(userId: sender.userId) }
                let name = user.map(ChatCache.displayName) ?? "User"
                let isBot: Bool = { if case .userTypeBot = user?.type { return true }; return false }()
                let role: MemberInfo.Role
                switch member.status {
                case .chatMemberStatusCreator: role = .owner
                case .chatMemberStatusAdministrator: role = .admin
                case .chatMemberStatusRestricted: role = .restricted
                default: role = .member
                }
                members.append(MemberInfo(
                    userID: UserID(sender.userId), name: name,
                    username: user?.usernames?.activeUsernames.first ?? "", role: role,
                    joinedAt: member.joinedChatDate > 0 ? Date(timeIntervalSince1970: TimeInterval(member.joinedChatDate)) : nil,
                    isBot: isBot))
            }
            if !query.isEmpty, identity.basic != nil {
                let q = query.lowercased()
                members = members.filter { $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q) }
            }
            return (members, total)
        }
    }

    /// Removes a member. With `ban`, they cannot rejoin until unbanned;
    /// without, they are removed and may come back through an invite link.
    public func removeMember(_ user: UserID, from chat: ChatID, ban: Bool) async throws(DomainError) {
        let sender = MessageSender.messageSenderUser(MessageSenderUser(userId: user.rawValue))
        let isSupergroup = cache.groupIdentity(chatId: chat.rawValue).supergroup != nil
        try await run {
            _ = try await self.client.banChatMember(bannedUntilDate: 0, chatId: chat.rawValue,
                                                    memberId: sender, revokeMessages: false)
            if !ban, isSupergroup {
                _ = try await self.client.setChatMemberStatus(chatId: chat.rawValue, memberId: sender,
                                                              status: .chatMemberStatusLeft)
            }
        }
    }

    // MARK: - Story viewers

    /// Everyone Telegram currently lists as having viewed one of the user's
    /// stories, with their reaction.
    public func storyViewers(_ storyID: Int) async -> [StoryViewer] {
        var result: [StoryViewer] = []
        var offset = ""
        for _ in 0..<20 {
            guard let page = try? await client.getStoryInteractions(
                limit: 100, offset: offset, onlyContacts: false, preferForwards: false,
                preferWithReaction: false, query: "", storyId: storyID) else { break }
            for interaction in page.interactions {
                guard case .messageSenderUser(let sender) = interaction.actorId else { continue }
                var reaction: String?
                if case .storyInteractionTypeView(let view) = interaction.type,
                   case .reactionTypeEmoji(let emoji)? = view.chosenReactionType {
                    reaction = emoji.emoji
                }
                var user = cache.user(sender.userId)
                if user == nil { user = try? await client.getUser(userId: sender.userId) }
                result.append(StoryViewer(
                    storyID: storyID, userID: sender.userId,
                    name: user.map(ChatCache.displayName) ?? "User",
                    viewedAt: Date(timeIntervalSince1970: TimeInterval(interaction.interactionDate)),
                    reaction: reaction, recordedAt: Date()))
            }
            offset = page.nextOffset
            if offset.isEmpty { break }
        }
        return result
    }
}
