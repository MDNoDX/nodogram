//  TelegramGateway — the single point in Nodogram that touches TDLib.
//
//  WHY `@unchecked Sendable` AND NOT AN ACTOR
//  ------------------------------------------
//  `TDLibKit.TDLibClient` is not Sendable, and its methods are
//  `nonisolated async`. Holding it in an `actor` does NOT help: the call still
//  *sends* the client out of the actor's isolation domain and fails to compile
//  under Swift 6.
//
//  Confinement is sound because of TDLib's documented C contract
//  (td/telegram/td_json_client.h):
//
//    - "share the client_id with other threads, which will be able to send
//       requests via td_send"           -> sending is thread-safe
//    - "This function [td_receive] must not be called simultaneously from two
//       different threads"              -> one receiver, owned by TDLibClientManager
//    - "all updates and responses ... must be applied in the order they were
//       received for consistency"       -> updates are never processed in parallel
//    - "All TDLib client instances must be closed before application
//       termination"                    -> shutdown() is mandatory
//
//  Every public method returns Sendable values only, so the client never escapes.
//  See Documentation/ARCHITECTURE.md §1.3 and §4.

import Foundation
import NodogramDomain
import TDLibKit
import TDLibFramework

/// TDLibKit also declares a `Date` type; in this file `Date` always means Foundation's.
private typealias Date = Foundation.Date

/// An ordered event from TDLib, already translated into domain terms.
public enum TelegramEvent: Sendable {
    case authorizationStateChanged(NodogramDomain.AuthorizationState)
    case connectionStateChanged(NodogramDomain.ConnectionState)
    case optionReceived(name: String, value: String)

    /// A full, current snapshot of one chat.
    case chatUpdated(NodogramDomain.Chat)
    /// A chat's small avatar finished downloading.
    case chatAvatarReady(ChatID, path: String)

    case messageAdded(NodogramDomain.Message)
    /// A pending message was confirmed (new id) or failed (`sendState` says so).
    case messageReplaced(old: MessageID, new: NodogramDomain.Message)
    case messagesDeleted(ChatID, [MessageID])
    case messageContentChanged(ChatID, MessageID, text: String, attachmentLabel: String?)
    case messageEdited(ChatID, MessageID, editDate: Foundation.Date)
    /// The other side has read every outgoing message up to and including this id.
    case outboxRead(ChatID, upTo: MessageID)

    /// A file's download progressed, finished, or was cancelled.
    case fileUpdated(MediaFile)
    /// Someone started or stopped typing, recording, etc. `nil` = stopped.
    case chatActivity(ChatID, user: UserID, activity: ChatActivity?)
    /// A poll's votes or state changed. `details` is empty here; keep the
    /// description already known from the message.
    case pollUpdated(PollContent)
    /// Views, forwards, reactions or comment count changed.
    case messageInteraction(ChatID, MessageID, views: Int, forwards: Int,
                            reactions: [ReactionSummary], comments: Int?)
    /// A chat's active stories changed; empty ids mean it has none now.
    case storiesChanged(StoryOwner)
    /// TDLib decided these should be shown as system notifications.
    case notificationsAdded([ChatNotification])
    /// These notifications were read or otherwise withdrawn; remove them.
    case notificationsRemoved(groupID: Int, ids: [Int])
    /// The user's chat folders, in order. `mainPosition` is where "All Chats"
    /// sits among them.
    case foldersChanged([ChatFolderSummary], mainPosition: Int)
    /// A user's name and usernames as just received, for name-history tracking.
    case userIdentity(UserID, UserIdentity)
    /// A contact relationship changed: they added or removed you.
    case contactChanged(UserID, name: String, nowMutual: Bool, wasMutual: Bool, isContact: Bool)
}

/// Which of Telegram's chat lists to load.
public enum ChatListKind: Hashable, Sendable {
    case main
    case archive
    case folder(Int)

    var tdList: ChatList {
        switch self {
        case .main: return .chatListMain
        case .archive: return .chatListArchive
        case .folder(let id): return .chatListFolder(ChatListFolder(chatFolderId: id))
        }
    }
}

public final class TelegramGateway: @unchecked Sendable {

    /// The process-wide TDLib manager.
    ///
    /// There must be EXACTLY ONE of these per process. Each `TDLibClientManager`
    /// starts its own `td_receive` loop, and TDLib's contract states that
    /// `td_receive` "must not be called simultaneously from two different
    /// threads" — two managers abort the process (verified: SIGABRT).
    ///
    /// TDLib's model is one receive loop with many clients, which is exactly
    /// what multi-account isolation needs: one client per account.
    ///
    /// `nonisolated(unsafe)` because `TDLibClientManager` is not `Sendable`, yet
    /// a single shared instance is what TDLib requires. It is created once and
    /// never reassigned, its client registry is a concurrent dictionary, and
    /// `td_send` is documented as callable from any thread.
    private nonisolated(unsafe) static let sharedManager: TDLibClientManager = {
        // TDLib's default verbosity writes tens of thousands of lines a minute,
        // and at that level it logs whole update objects — message text
        // included. That is both a privacy leak into system logs and a real
        // CPU cost, so only errors are kept. `td_execute` is synchronous and
        // documented as safe from any thread, and runs before any client exists.
        _ = td_execute(#"{"@type":"setLogVerbosityLevel","new_verbosity_level":1}"#)
        return TDLibClientManager()
    }()

    /// This gateway's own client. One per account.
    let client: TDLibClient

    /// Client-side mirror of TDLib's chat state, maintained from updates.
    let cache: ChatCache

    /// The single ordered event stream, delivered in batches.
    ///
    /// TDLib requires updates be applied in receive order, so there is one
    /// stream with one consumer. Events are coalesced over ~16 ms (one frame):
    /// at startup TDLib sends thousands of updates, and handing them to the UI
    /// one at a time would re-render the chat list thousands of times.
    public let events: AsyncStream<[TelegramEvent]>
    private let emitter: EventEmitter
    /// Fires when TDLib reports `authorizationStateClosed`.
    private let closed = ClosedSignal()

    public init() {
        let (stream, continuation) = AsyncStream<[TelegramEvent]>.makeStream(
            // Buffer rather than drop: losing an update would desynchronise
            // state, which is worse than briefly using more memory.
            bufferingPolicy: .unbounded
        )
        let cache = ChatCache()
        let emitter = EventEmitter(continuation: continuation)
        let closed = self.closed
        self.events = stream
        self.emitter = emitter
        self.cache = cache

        self.client = Self.sharedManager.createClient { data, _ in
            // Invoked on TDLibKit's per-client serial queue — already ordered.
            Self.handle(data: data, cache: cache, emitter: emitter, closed: closed)
        }
    }

    // MARK: - Lifecycle

    /// Sends `setTdlibParameters`, without which every account request fails
    /// with error 400 (verified; see ARCHITECTURE.md §1.2).
    public func initialize(
        credentials: TelegramCredentials,
        databaseDirectory: URL,
        filesDirectory: URL,
        encryptionKey: Data = Data()
    ) async throws(DomainError) {
        try await run {
            _ = try await self.client.setTdlibParameters(
                apiHash: credentials.apiHash,
                apiId: credentials.apiID,
                applicationVersion: Self.applicationVersion,
                databaseDirectory: databaseDirectory.path,
                databaseEncryptionKey: encryptionKey,
                deviceModel: Self.deviceModel,
                filesDirectory: filesDirectory.path,
                systemLanguageCode: Self.systemLanguageCode,
                systemVersion: Self.systemVersion,
                useChatInfoDatabase: true,
                useFileDatabase: true,
                useMessageDatabase: true,
                useSecretChats: false,
                useTestDc: false
            )
        }
    }

    /// Closes THIS gateway's client. Required before termination, per TDLib's
    /// contract. Deliberately not `closeClients()`, which closes every client
    /// in the process and then busy-waits on them.
    public func shutdown() {
        try? client.close { _ in }
        emitter.finish()
    }

    /// Closes TDLib and waits until it reports the database closed (or the
    /// timeout passes). Quitting before that risks the database, and C++
    /// teardown racing TDLib's receive thread crashed the app on exit.
    public func closeAndWait(timeout: TimeInterval = 4) async {
        try? client.close { _ in }
        await closed.wait(timeout: timeout)
        emitter.finish()
    }

    // MARK: - Authentication

    public func tdlibVersion() async throws(DomainError) -> String {
        try await run {
            guard case .optionValueString(let value) = try await self.client.getOption(name: "version")
            else { return "unknown" }
            return value.value
        }
    }

    public func currentAuthorizationState() async throws(DomainError)
        -> NodogramDomain.AuthorizationState? {
        try await run { AuthorizationMapping.map(try await self.client.getAuthorizationState()) }
    }

    public func setPhoneNumber(_ phoneNumber: String) async throws(DomainError) {
        try await run {
            _ = try await self.client.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: nil)
        }
    }

    public func checkCode(_ code: String) async throws(DomainError) {
        try await run { _ = try await self.client.checkAuthenticationCode(code: code) }
    }

    public func checkPassword(_ password: String) async throws(DomainError) {
        try await run { _ = try await self.client.checkAuthenticationPassword(password: password) }
    }

    /// The signed-in user's id. In TDLib, "Saved Messages" is the private chat
    /// whose id equals this.
    public func myUserID() async throws(DomainError) -> UserID {
        let id = try await run { try await self.client.getMe().id }
        if let saved = cache.setMyUserId(id) {
            emitter.emit([.chatUpdated(saved)])
        }
        return UserID(id)
    }

    public func logOut() async throws(DomainError) {
        try await run { _ = try await self.client.logOut() }
    }

    // MARK: - Chats

    /// Asks TDLib to load more chats into a list. The chats themselves arrive
    /// as `chatUpdated` events, not as a return value — that is TDLib's design.
    ///
    /// - Returns: `false` once the list is fully loaded (TDLib signals this with
    ///   error 404), so callers can stop asking.
    public func loadChats(_ list: ChatListKind, limit: Int) async throws(DomainError) -> Bool {
        do {
            _ = try await client.loadChats(
                chatList: list.tdList,
                limit: limit
            )
            return true
        } catch let error as TDLibKit.Error where error.code == 404 {
            return false
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Makes sure TDLib has a chat object for a private conversation — used for
    /// Saved Messages, which may not be among the chats loaded so far. The chat
    /// itself arrives as a `chatUpdated` event.
    public func ensurePrivateChat(with user: UserID) async {
        _ = try? await client.createPrivateChat(force: false, userId: user.rawValue)
    }

    /// Tells TDLib the chat is on screen, so it delivers live updates for it.
    public func openChat(_ chat: ChatID) async {
        _ = try? await client.openChat(chatId: chat.rawValue)
    }

    public func closeChat(_ chat: ChatID) async {
        _ = try? await client.closeChat(chatId: chat.rawValue)
    }

    /// Marks messages as read. Best-effort: failing to mark read must never
    /// block reading.
    public func markRead(_ chat: ChatID, messages: [MessageID]) async {
        guard !messages.isEmpty else { return }
        _ = try? await client.viewMessages(
            chatId: chat.rawValue,
            forceRead: true,
            messageIds: messages.map(\.rawValue),
            source: nil
        )
    }

    /// Downloads a chat's small avatar if it is not on disk yet. The result
    /// arrives as a `chatAvatarReady` event.
    public func ensureAvatar(_ chat: ChatID) async {
        guard let fileId = cache.smallPhotoFileId(chatId: chat.rawValue) else { return }
        guard let file = try? await client.downloadFile(
            fileId: fileId, limit: 0, offset: 0, priority: 1, synchronous: true
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }

        _ = cache.setAvatarPath(file.local.path, chatId: chat.rawValue)
        // A targeted event rather than a full chat snapshot: a snapshot taken on
        // this thread could arrive after a newer one from the update queue and
        // roll the chat back.
        emitter.emit([.chatAvatarReady(chat, path: file.local.path)])
    }

    // MARK: - Messages

    /// Loads messages older than `before` (or the newest, if `nil`), oldest first.
    ///
    /// TDLib deliberately returns fewer messages than asked — often just one on
    /// the first call, straight from its local database — so this keeps asking
    /// until it has enough or the history is exhausted.
    public func history(
        _ chat: ChatID,
        before: MessageID?,
        limit: Int = 50
    ) async throws(DomainError) -> [NodogramDomain.Message] {
        try await run {
            var collected: [TDLibKit.Message] = []
            var seen = Set<Int64>()
            var cursor = before?.rawValue ?? 0

            for _ in 0..<8 where collected.count < limit {
                let batch = try await self.client.getChatHistory(
                    chatId: chat.rawValue,
                    fromMessageId: cursor,
                    limit: min(100, limit - collected.count),
                    offset: 0,
                    onlyLocal: false
                )
                let messages = (batch.messages ?? []).filter { seen.insert($0.id).inserted }
                guard let oldest = messages.last else { break }
                collected += messages
                cursor = oldest.id
            }

            return collected
                .map(self.cache.mapMessage)
                .sorted { $0.id.rawValue < $1.id.rawValue }
        }
    }

    public func sendText(_ text: String, to chat: ChatID, replyTo: MessageID? = nil,
                         thread: Int64? = nil, silent: Bool = false, scheduleAt: Foundation.Date? = nil) async throws(DomainError) {
        let options: MessageSendOptions? = (silent || scheduleAt != nil) ? MessageSendOptions(
            allowPaidBroadcast: false, disableNotification: silent, effectId: TdInt64(0), fromBackground: false,
            onlyPreview: false, paidMessageStarCount: 0, protectContent: false,
            schedulingState: scheduleAt.map { .messageSchedulingStateSendAtDate(
                MessageSchedulingStateSendAtDate(repeatPeriod: 0, sendDate: Int($0.timeIntervalSince1970))) },
            sendingId: 0, suggestedPostInfo: nil, updateOrderOfInstalledStickerSets: false) : nil
        try await run {
            // The pending message arrives through `updateNewMessage`, and its
            // confirmation through `updateMessageSendSucceeded`; the return value
            // is intentionally unused so there is one path, not two.
            _ = try await self.client.sendMessage(
                chatId: chat.rawValue,
                inputMessageContent: .inputMessageText(InputMessageText(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: text)
                )),
                options: options,
                replyMarkup: nil,
                replyTo: replyTo.map {
                    .inputMessageReplyToMessage(InputMessageReplyToMessage(
                        checklistTaskId: 0, messageId: $0.rawValue, pollOptionId: "", quote: nil))
                },
                topicId: thread.map { .messageTopicThread(MessageTopicThread(messageThreadId: $0)) }
            )
        }
    }

    /// Saves the composer's text as the chat's Telegram draft, so it survives
    /// restarts and appears on the user's other devices. Empty text clears it.
    public func setDraft(_ text: String, chat: ChatID) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft: DraftMessage? = trimmed.isEmpty ? nil : DraftMessage(
            content: .draftMessageContentText(DraftMessageContentText(
                linkPreviewOptions: nil,
                text: FormattedText(entities: [], text: text)
            )),
            date: Int(Date().timeIntervalSince1970),
            effectId: 0,
            replyTo: nil,
            suggestedPostInfo: nil
        )
        _ = try? await client.setChatDraftMessage(chatId: chat.rawValue, draftMessage: draft, topicId: nil)
    }

    /// The exact time an outgoing message was read, where Telegram will say.
    /// Returns `nil` when the question cannot be asked (e.g. in groups).
    public func readDate(_ chat: ChatID, message: MessageID) async -> NodogramDomain.MessageReadDate? {
        guard let result = try? await client.getMessageReadDate(
            chatId: chat.rawValue, messageId: message.rawValue
        ) else { return nil }

        switch result {
        case .messageReadDateRead(let v):
            return .read(Date(timeIntervalSince1970: TimeInterval(v.readDate)))
        case .messageReadDateUnread:
            return .unread
        case .messageReadDateTooOld:
            return .tooOld
        case .messageReadDateUserPrivacyRestricted:
            return .recipientPrivacyRestricted
        case .messageReadDateMyPrivacyRestricted:
            return .ownPrivacyRestricted
        }
    }

    // MARK: - Database encryption

    /// Re-encrypts TDLib's database under a new key. Used once to move an
    /// existing unencrypted database to an encrypted one.
    public func setDatabaseKey(_ key: Data) async throws(DomainError) {
        try await run { _ = try await self.client.setDatabaseEncryptionKey(newEncryptionKey: key) }
    }

    /// Messages waiting to be sent at a set time, in one chat.
    public func scheduledMessages(in chat: ChatID) async -> [NodogramDomain.Message] {
        let found = try? await client.getChatScheduledMessages(chatId: chat.rawValue)
        return (found?.messages ?? []).compactMap { $0 }.map(cache.mapMessage)
    }

    public func sendScheduledNow(_ message: MessageID, in chat: ChatID) async throws(DomainError) {
        try await run {
            _ = try await self.client.editMessageSchedulingState(chatId: chat.rawValue, messageId: message.rawValue, schedulingState: nil)
        }
    }

    public func deleteScheduled(_ messages: [MessageID], in chat: ChatID) async throws(DomainError) {
        try await run { _ = try await self.client.deleteMessages(chatId: chat.rawValue, messageIds: messages.map(\.rawValue), revoke: true) }
    }

    // MARK: - Presence

    /// Tells Telegram whether the user is using the app right now. Official
    /// clients set this on focus changes; without it the user would always
    /// appear offline, which the API terms (1.4) count as wrong status display.
    public func setOnline(_ online: Bool) async {
        _ = try? await client.setOption(name: "online", value: .optionValueBoolean(OptionValueBoolean(value: online)))
    }

    // MARK: - Notifications

    /// TDLib sends no notification updates until this is set. It then applies
    /// the user's mute settings, mention rules and exceptions itself, so the
    /// app shows exactly what the official clients would.
    public func enableNotifications() async {
        _ = try? await client.setOption(name: "notification_group_count_max", value: .optionValueInteger(OptionValueInteger(value: TdInt64(25))))
        _ = try? await client.setOption(name: "notification_group_size_max", value: .optionValueInteger(OptionValueInteger(value: TdInt64(10))))
    }

    // MARK: - Chat actions

    /// Mutes "forever" (Telegram's convention: a very long period) or unmutes.
    public func setMuted(_ muted: Bool, chat: ChatID) async throws(DomainError) {
        guard let current = cache.notificationSettings(chatId: chat.rawValue) else { return }
        let updated = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: muted ? 366 * 86_400 : 0,
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: current.soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound,
            useDefaultStorySound: current.useDefaultStorySound)
        try await run { _ = try await self.client.setChatNotificationSettings(chatId: chat.rawValue, notificationSettings: updated) }
    }

    public func setPinned(_ pinned: Bool, chat: ChatID) async throws(DomainError) {
        try await run { _ = try await self.client.toggleChatIsPinned(chatId: chat.rawValue, chatList: .chatListMain, isPinned: pinned) }
    }

    public func setMarkedUnread(_ unread: Bool, chat: ChatID) async throws(DomainError) {
        try await run { _ = try await self.client.toggleChatIsMarkedAsUnread(chatId: chat.rawValue, isMarkedAsUnread: unread) }
    }

    public func setArchived(_ archived: Bool, chat: ChatID) async throws(DomainError) {
        try await run {
            _ = try await self.client.addChatToList(chatId: chat.rawValue, chatList: archived ? .chatListArchive : .chatListMain)
        }
    }

    // MARK: - Sponsored messages

    public func sponsoredMessages(in chat: ChatID) async -> (items: [SponsoredItem], between: Int) {
        guard let result = try? await client.getChatSponsoredMessages(chatId: chat.rawValue) else { return ([], 0) }
        let items = result.messages.map { ad -> SponsoredItem in
            let mapped = ContentMapping.map(ad.content)
            return SponsoredItem(
                id: MessageID(ad.messageId), title: ad.title, text: mapped.text, entities: mapped.entities,
                buttonText: ad.buttonText, url: ad.sponsor.url, sponsorInfo: ad.sponsor.info,
                additionalInfo: ad.additionalInfo, isRecommended: ad.isRecommended,
                media: MediaMapping.media(ad.content))
        }
        return (items, result.messagesBetween)
    }

    /// Reports an ad as seen. Called only once its whole text is on screen,
    /// as Telegram's documentation requires.
    public func markSponsoredViewed(_ item: MessageID, in chat: ChatID) async {
        _ = try? await client.viewMessages(chatId: chat.rawValue, forceRead: false, messageIds: [item.rawValue], source: nil)
    }

    public func clickSponsored(_ item: MessageID, in chat: ChatID, media: Bool) async {
        _ = try? await client.clickChatSponsoredMessage(chatId: chat.rawValue, fromFullscreen: false,
                                                        isMediaClick: media, messageId: item.rawValue)
    }

    // MARK: - Sending files

    public func sendFile(_ file: OutgoingFile, caption: String, to chat: ChatID,
                         replyTo: MessageID? = nil) async throws(DomainError) {
        let input = InputFile.inputFileLocal(InputFileLocal(path: file.path))
        let text: FormattedText? = caption.isEmpty ? nil : FormattedText(entities: [], text: caption)
        let content: InputMessageContent
        switch file.kind {
        case .photo:
            content = .inputMessagePhoto(InputMessagePhoto(
                caption: text, hasSpoiler: false,
                photo: InputPhoto(addedStickerFileIds: [], height: file.height, photo: input,
                                  thumbnail: nil, video: nil, width: file.width),
                selfDestructType: nil, showCaptionAboveMedia: false))
        case .video:
            content = .inputMessageVideo(InputMessageVideo(
                caption: text, hasSpoiler: false, selfDestructType: nil, showCaptionAboveMedia: false,
                video: InputVideo(addedStickerFileIds: [], cover: nil, duration: file.duration,
                                  height: file.height, startTimestamp: 0, supportsStreaming: true,
                                  thumbnail: nil, video: input, width: file.width)))
        case .document:
            content = .inputMessageDocument(InputMessageDocument(
                caption: text,
                document: InputDocument(disableContentTypeDetection: false, document: input, thumbnail: nil)))
        }
        try await run {
            _ = try await self.client.sendMessage(
                chatId: chat.rawValue, inputMessageContent: content, options: nil, replyMarkup: nil,
                replyTo: replyTo.map {
                    .inputMessageReplyToMessage(InputMessageReplyToMessage(
                        checklistTaskId: 0, messageId: $0.rawValue, pollOptionId: "", quote: nil))
                },
                topicId: nil)
        }
    }

    // MARK: - Search

    /// Searches one chat's messages, newest first.
    public func search(_ query: String, in chat: ChatID, from: MessageID? = nil,
                       limit: Int = 50) async throws(DomainError) -> (messages: [NodogramDomain.Message], next: MessageID?) {
        try await run {
            let found = try await self.client.searchChatMessages(
                chatId: chat.rawValue, filter: nil, fromMessageId: from?.rawValue ?? 0,
                limit: limit, offset: 0, query: query, senderId: nil, topicId: nil)
            return (found.messages.map(self.cache.mapMessage),
                    found.nextFromMessageId == 0 ? nil : MessageID(found.nextFromMessageId))
        }
    }

    /// Searches every chat. Telegram applies its own ranking.
    public func searchEverywhere(_ query: String, offset: String = "", limit: Int = 40) async throws(DomainError)
        -> (messages: [NodogramDomain.Message], nextOffset: String) {
        try await run {
            let found = try await self.client.searchMessages(
                chatList: nil, chatTypeFilter: nil, filter: nil, limit: limit,
                maxDate: 0, minDate: 0, offset: offset, query: query)
            return (found.messages.map(self.cache.mapMessage), found.nextOffset)
        }
    }

    /// One kind of content in one chat — what the Media/Files/Links/Voice
    /// sections are built from when Telegram's global search ignores a filter.
    public func searchContent(_ filter: MediaFilter, in chat: ChatID, limit: Int = 20) async throws(DomainError)
        -> [NodogramDomain.Message] {
        try await run {
            let found = try await self.client.searchChatMessages(
                chatId: chat.rawValue, filter: Self.tdFilter(filter), fromMessageId: 0,
                limit: limit, offset: 0, query: "", senderId: nil, topicId: nil)
            return found.messages.map(self.cache.mapMessage)
        }
    }

    // MARK: - Polls

    /// Casts a vote. `options` are Telegram option indexes (`Option.index`),
    /// not display positions. An empty list retracts the vote.
    public func vote(_ options: [Int], on message: MessageID, in chat: ChatID) async throws(DomainError) {
        try await run {
            _ = try await self.client.setPollAnswer(
                chatId: chat.rawValue, messageId: message.rawValue, optionIds: options)
        }
    }

    /// Recent polls in one chat, newest first. Telegram's *global* search
    /// ignores the poll filter (verified: it returned photos and videos), so
    /// polls must be searched per chat. Searching marks nothing as read.
    public func polls(in chat: ChatID, limit: Int = 5) async throws(DomainError) -> [NodogramDomain.Message] {
        try await run {
            let found = try await self.client.searchChatMessages(
                chatId: chat.rawValue, filter: .searchMessagesFilterPoll, fromMessageId: 0,
                limit: limit, offset: 0, query: "", senderId: nil, topicId: nil)
            return found.messages.map(self.cache.mapMessage)
        }
    }
    // MARK: - History around a message

    /// Messages surrounding `message`, for jumping to a search result or a
    /// replied-to message that is not loaded.
    public func history(around message: MessageID, in chat: ChatID, limit: Int = 40) async throws(DomainError)
        -> [NodogramDomain.Message] {
        try await run {
            let batch = try await self.client.getChatHistory(
                chatId: chat.rawValue, fromMessageId: message.rawValue,
                limit: limit, offset: -(limit / 2), onlyLocal: false)
            return (batch.messages ?? []).map(self.cache.mapMessage).sorted { $0.id.rawValue < $1.id.rawValue }
        }
    }

    /// Messages newer than `after`, oldest first — used when the user scrolls
    /// down after jumping into older history.
    public func history(after: MessageID, in chat: ChatID, limit: Int = 50) async throws(DomainError)
        -> [NodogramDomain.Message] {
        try await run {
            let batch = try await self.client.getChatHistory(
                chatId: chat.rawValue, fromMessageId: after.rawValue,
                limit: limit, offset: -(limit - 1), onlyLocal: false)
            return (batch.messages ?? [])
                .filter { $0.id > after.rawValue }
                .map(self.cache.mapMessage)
                .sorted { $0.id.rawValue < $1.id.rawValue }
        }
    }

    public func repliedMessage(to message: MessageID, in chat: ChatID) async -> NodogramDomain.Message? {
        guard let replied = try? await client.getRepliedMessage(chatId: chat.rawValue, messageId: message.rawValue)
        else { return nil }
        return cache.mapMessage(replied)
    }

    /// Makes sure a chat is known locally, e.g. one that appears only in
    /// search results. It arrives as a `chatUpdated` event.
    public func ensureChat(_ chat: ChatID) async {
        _ = try? await client.getChat(chatId: chat.rawValue)
    }

    public func chatTitle(_ chat: ChatID) -> String? {
        cache.title(of: chat.rawValue)
    }

    // MARK: - Reactions

    public func setReaction(_ kind: ReactionSummary.Kind, on message: MessageID, in chat: ChatID,
                            add: Bool) async throws(DomainError) {
        let type: ReactionType
        switch kind {
        case .emoji(let emoji): type = .reactionTypeEmoji(ReactionTypeEmoji(emoji: emoji))
        case .customEmoji(let id): type = .reactionTypeCustomEmoji(ReactionTypeCustomEmoji(customEmojiId: TdInt64(id)))
        case .paid: return   // Paid reactions spend Stars; never sent from a click.
        }
        try await run {
            if add {
                _ = try await self.client.addMessageReaction(
                    chatId: chat.rawValue, isBig: false, messageId: message.rawValue,
                    reactionType: type, updateRecentReactions: true)
            } else {
                _ = try await self.client.removeMessageReaction(
                    chatId: chat.rawValue, messageId: message.rawValue, reactionType: type)
            }
        }
    }

    /// Reactions this chat allows on this message, most relevant first.
    public func availableReactions(for message: MessageID, in chat: ChatID) async -> [ReactionSummary.Kind] {
        guard let available = try? await client.getMessageAvailableReactions(
            chatId: chat.rawValue, messageId: message.rawValue, rowSize: 8) else { return [] }
        var seen = Set<ReactionSummary.Kind>()
        return (available.topReactions + available.recentReactions + available.popularReactions)
            .filter { !$0.needsPremium }
            .compactMap { reaction -> ReactionSummary.Kind? in
                switch reaction.type {
                case .reactionTypeEmoji(let e): return .emoji(e.emoji)
                case .reactionTypeCustomEmoji(let c): return .customEmoji(c.customEmojiId.rawValue)
                case .reactionTypePaid: return nil
                }
            }
            .filter { seen.insert($0).inserted }
    }

    /// The still image for a custom emoji, used to draw custom reactions.
    public func customEmojiImage(_ id: Int64) async -> MediaFile? {
        guard let stickers = try? await client.getCustomEmojiStickers(customEmojiIds: [TdInt64(id)]),
              let sticker = stickers.stickers.first else { return nil }
        let file: TDLibKit.File
        if case .stickerFormatWebp = sticker.format {
            file = sticker.sticker
        } else if let thumb = sticker.thumbnail, MediaMapping.displayableThumbnail(thumb) != nil {
            file = thumb.file
        } else {
            return nil
        }
        return await downloadAndWait(file.id, priority: 4) ?? MediaMapping.file(file)
    }

    // MARK: - Forward, link, edit, delete

    /// Forwards messages. Hiding the sender sends a copy, as if written by the
    /// user; hiding captions additionally strips media captions — Telegram's
    /// own two options.
    public func forward(_ messages: [MessageID], from source: ChatID, to targets: [ChatID],
                        options: ForwardOptions) async throws(DomainError) {
        for target in targets {
            try await run {
                _ = try await self.client.forwardMessages(
                    chatId: target.rawValue,
                    fromChatId: source.rawValue,
                    messageIds: messages.map(\.rawValue),
                    options: nil,
                    removeCaption: !options.showSender && !options.showCaptions,
                    sendCopy: !options.showSender,
                    topicId: nil)
            }
        }
    }

    /// A t.me link to the message — available for channels and public groups.
    public func messageLink(_ message: MessageID, in chat: ChatID) async -> String? {
        try? await client.getMessageLink(
            chatId: chat.rawValue, checklistTaskId: 0, forAlbum: false, inMessageThread: false,
            mediaTimestamp: 0, messageId: message.rawValue, pollOptionId: "").link
    }

    public func deleteMessages(_ messages: [MessageID], in chat: ChatID, forEveryone: Bool) async throws(DomainError) {
        try await run {
            _ = try await self.client.deleteMessages(
                chatId: chat.rawValue, messageIds: messages.map(\.rawValue), revoke: forEveryone)
        }
    }

    public func editText(_ message: MessageID, in chat: ChatID, text: String) async throws(DomainError) {
        try await run {
            _ = try await self.client.editMessageText(
                chatId: chat.rawValue,
                inputMessageContent: .inputMessageText(InputMessageText(
                    clearDraft: false, linkPreviewOptions: nil, text: FormattedText(entities: [], text: text))),
                messageId: message.rawValue,
                replyMarkup: nil)
        }
    }

    public struct MessagePermissions: Sendable {
        public let canEdit: Bool
        public let canDeleteForEveryone: Bool
        public let canDeleteForSelf: Bool
        public let canForward: Bool
        public let canReply: Bool
        public let canGetLink: Bool
    }

    public func permissions(for message: MessageID, in chat: ChatID) async -> MessagePermissions? {
        guard let p = try? await client.getMessageProperties(chatId: chat.rawValue, messageId: message.rawValue)
        else { return nil }
        return MessagePermissions(
            canEdit: p.canBeEdited, canDeleteForEveryone: p.canBeDeletedForAllUsers,
            canDeleteForSelf: p.canBeDeletedOnlyForSelf, canForward: p.canBeForwarded,
            canReply: p.canBeReplied, canGetLink: p.canGetLink)
    }

    public func translate(_ text: String, to language: String) async -> String? {
        try? await client.translateText(
            text: FormattedText(entities: [], text: text), toLanguageCode: language, tone: nil).text
    }

    // MARK: - Comments

    public struct CommentThread: Sendable {
        /// The discussion group the comments live in.
        public let chatID: ChatID
        public let threadID: Int64
    }

    public func commentThread(for message: MessageID, in chat: ChatID) async throws(DomainError) -> CommentThread {
        try await run {
            let info = try await self.client.getMessageThread(chatId: chat.rawValue, messageId: message.rawValue)
            return CommentThread(chatID: ChatID(info.chatId), threadID: info.messageThreadId)
        }
    }

    /// Comments on a channel post, oldest first.
    public func comments(on message: MessageID, in chat: ChatID, before: MessageID? = nil,
                         limit: Int = 50) async throws(DomainError) -> [NodogramDomain.Message] {
        try await run {
            var collected: [TDLibKit.Message] = []
            var seen = Set<Int64>()
            var cursor = before?.rawValue ?? 0
            for _ in 0..<6 where collected.count < limit {
                let batch = try await self.client.getMessageThreadHistory(
                    chatId: chat.rawValue, fromMessageId: cursor,
                    limit: min(100, limit - collected.count),
                    messageId: message.rawValue, offset: 0)
                let fresh = (batch.messages ?? []).filter { seen.insert($0.id).inserted }
                guard let oldest = fresh.last else { break }
                collected += fresh
                cursor = oldest.id
            }
            return collected.map(self.cache.mapMessage).sorted { $0.id.rawValue < $1.id.rawValue }
        }
    }

    // MARK: - Global search

    public enum MediaFilter: Sendable {
        case photosAndVideos, files, links, voice, music
    }

    /// Searches all chats for one kind of content. `offset` is TDLib's paging
    /// cursor: pass back `nextOffset` for the next page.
    public func searchAll(_ filter: MediaFilter, query: String = "", offset: String = "",
                          limit: Int = 60) async throws(DomainError) -> (messages: [NodogramDomain.Message], nextOffset: String) {
        let tdFilter = Self.tdFilter(filter)
        return try await run {
            let found = try await self.client.searchMessages(
                chatList: nil, chatTypeFilter: nil, filter: tdFilter, limit: limit,
                maxDate: 0, minDate: 0, offset: offset, query: query)
            return (found.messages.map(self.cache.mapMessage), found.nextOffset)
        }
    }

    private static func tdFilter(_ filter: MediaFilter) -> SearchMessagesFilter {
        switch filter {
        case .photosAndVideos: return .searchMessagesFilterPhotoAndVideo
        case .files: return .searchMessagesFilterDocument
        case .links: return .searchMessagesFilterUrl
        case .voice: return .searchMessagesFilterVoiceNote
        case .music: return .searchMessagesFilterAudio
        }
    }

    // MARK: - Stories

    public func loadStories() async {
        _ = try? await client.loadActiveStories(storyList: .storyListMain)
    }

    public func story(_ id: Int, of chat: ChatID) async -> StoryItem? {
        guard let story = try? await client.getStory(onlyLocal: false, storyId: id, storyPosterChatId: chat.rawValue)
        else { return nil }
        let content: StoryItem.Content = {
            switch story.content {
            case .storyContentPhoto(let p):
                return MediaMapping.photo(p.photo).map(StoryItem.Content.photo) ?? .unsupported
            case .storyContentVideo(let v):
                let video = v.video
                return .video(VideoMedia(
                    file: MediaMapping.file(video.video),
                    thumbnail: MediaMapping.displayableThumbnail(video.thumbnail),
                    minithumbnail: video.minithumbnail?.data,
                    width: video.width, height: video.height, duration: Int(video.duration.rounded()),
                    mimeType: "video/mp4", fileName: "", supportsStreaming: true))
            default:
                return .unsupported
            }
        }()
        return StoryItem(
            id: story.id, chatID: chat,
            date: Date(timeIntervalSince1970: TimeInterval(story.date)),
            caption: story.caption.text, entities: MediaMapping.entities(story.caption),
            content: content)
    }

    /// Opening a story marks it viewed — the poster sees that, exactly as in
    /// Telegram. Called only when the user actually opens one.
    public func markStoryOpened(_ id: Int, of chat: ChatID) async {
        _ = try? await client.openStory(storyId: id, storyPosterChatId: chat.rawValue)
    }

    public func markStoryClosed(_ id: Int, of chat: ChatID) async {
        _ = try? await client.closeStory(storyId: id, storyPosterChatId: chat.rawValue)
    }

    // MARK: - Files

    /// Starts (or reprioritises) a download. Progress arrives as `fileUpdated`
    /// events. Higher priority (1…32) is fetched first.
    public func startDownload(_ fileID: Int, priority: Int = 8) async {
        _ = try? await client.downloadFile(fileId: fileID, limit: 0, offset: 0, priority: priority, synchronous: false)
    }

    /// Downloads a small file and waits for it — for thumbnails, photos and
    /// voice messages, where waiting is shorter than wiring up progress.
    public func downloadAndWait(_ fileID: Int, priority: Int = 16) async -> MediaFile? {
        guard let file = try? await client.downloadFile(
            fileId: fileID, limit: 0, offset: 0, priority: priority, synchronous: true
        ) else { return nil }
        return MediaMapping.file(file)
    }

    public func cancelDownload(_ fileID: Int) async {
        _ = try? await client.cancelDownloadFile(fileId: fileID, onlyIfPending: false)
    }

    // MARK: - Update handling

    /// TDLibKit's own decoding configuration, so there is one decoder of record
    /// for both requests and updates.
    static func decodeUpdate(_ data: Data) throws -> Update {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Update.self, from: data)
    }

    /// `static` so it cannot capture `self`, and with it the non-Sendable client.
    private static func handle(
        data: Data,
        cache: ChatCache,
        emitter: EventEmitter,
        closed: ClosedSignal
    ) {
        // Responses to requests carry "@extra" and are routed by TDLibKit before
        // reaching here; anything that fails to decode is not an update we model.
        guard let update = try? decodeUpdate(data) else { return }

        switch update {
        case .updateAuthorizationState(let u):
            if case .authorizationStateClosed = u.authorizationState { closed.fire() }
            if let state = AuthorizationMapping.map(u.authorizationState) {
                emitter.emit([.authorizationStateChanged(state)])
            }
        case .updateConnectionState(let u):
            emitter.emit([.connectionStateChanged(mapConnection(u.state))])
        case .updateOption(let u):
            if case .optionValueString(let value) = u.value {
                emitter.emit([.optionReceived(name: u.name, value: value.value)])
            }
        default:
            let events = cache.apply(update)
            if !events.isEmpty { emitter.emit(events) }
        }
    }

    private static func mapConnection(_ state: TDLibKit.ConnectionState) -> NodogramDomain.ConnectionState {
        switch state {
        case .connectionStateReady: return .connected
        case .connectionStateConnecting: return .connecting
        case .connectionStateConnectingToProxy: return .connectingToProxy
        case .connectionStateUpdating: return .updating
        case .connectionStateWaitingForNetwork: return .offline
        }
    }

    /// Runs a TDLib request, translating any failure into a `DomainError` so no
    /// TDLib error type escapes this layer.
    func run<T>(_ body: () async throws -> T) async throws(DomainError) -> T {
        do {
            return try await body()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    // MARK: - Device description sent to Telegram

    private static var applicationVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    private static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private static var systemLanguageCode: String {
        Locale.preferredLanguages.first ?? "en"
    }
}


// MARK: - Streaming

extension TelegramGateway: MediaByteSource {

    /// Ensures a byte range is on disk, for streaming playback.
    ///
    /// TDLib returns early from a synchronous `downloadFile` when another
    /// request for the same file changes the offset or limit — which a video
    /// player does constantly while seeking. So the return value is not
    /// trusted: availability is confirmed with `getFileDownloadedPrefixSize`
    /// and the request repeated until the bytes are really there.
    public func prepareRange(fileID: Int, offset: Int64, length: Int64, priority: Int) async throws {
        guard length > 0 else { return }
        for _ in 0..<60 {
            try Task.checkCancellation()
            let available = try await client.getFileDownloadedPrefixSize(fileId: fileID, offset: offset).size
            if available >= length { return }
            _ = try await client.downloadFile(
                fileId: fileID, limit: length, offset: offset, priority: priority, synchronous: true)
        }
        throw DomainError.storageFailure(detail: "Bytes \(offset)+\(length) of file \(fileID) did not become available")
    }

    public func readRange(fileID: Int, offset: Int64, count: Int64) async throws -> Data {
        try await client.readFilePart(count: count, fileId: fileID, offset: offset).data
    }
}

/// Coalesces events into per-frame batches on one serial queue, so ordering is
/// preserved exactly while the UI is updated at most once per frame.
private final class EventEmitter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.nodogram.telegram.events")
    private let continuation: AsyncStream<[TelegramEvent]>.Continuation
    private var pending: [TelegramEvent] = []
    private var flushScheduled = false

    init(continuation: AsyncStream<[TelegramEvent]>.Continuation) {
        self.continuation = continuation
    }

    func emit(_ events: [TelegramEvent]) {
        queue.async {
            self.pending.append(contentsOf: events)
            guard !self.flushScheduled else { return }
            self.flushScheduled = true
            self.queue.asyncAfter(deadline: .now() + .milliseconds(16)) {
                let batch = self.pending
                self.pending = []
                self.flushScheduled = false
                if !batch.isEmpty { self.continuation.yield(batch) }
            }
        }
    }

    func finish() {
        queue.async { self.continuation.finish() }
    }
}

/// A one-shot signal that can be awaited with a timeout, resumed exactly once
/// per waiter whichever comes first.
final class ClosedSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func fire() {
        lock.lock()
        fired = true
        let pending = Array(waiters.values)
        waiters = [:]
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func wait(timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                continuation.resume()
                return
            }
            let token = UUID()
            waiters[token] = continuation
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resume(token)
            }
        }
    }

    private func resume(_ token: UUID) {
        lock.lock()
        let continuation = waiters.removeValue(forKey: token)
        lock.unlock()
        continuation?.resume()
    }
}
