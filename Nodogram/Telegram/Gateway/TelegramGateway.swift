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
}

/// Which of Telegram's chat lists to load.
public enum ChatListKind: Sendable {
    case main
    case archive
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
    private let client: TDLibClient

    /// Client-side mirror of TDLib's chat state, maintained from updates.
    private let cache: ChatCache

    /// The single ordered event stream, delivered in batches.
    ///
    /// TDLib requires updates be applied in receive order, so there is one
    /// stream with one consumer. Events are coalesced over ~16 ms (one frame):
    /// at startup TDLib sends thousands of updates, and handing them to the UI
    /// one at a time would re-render the chat list thousands of times.
    public let events: AsyncStream<[TelegramEvent]>
    private let emitter: EventEmitter

    public init() {
        let (stream, continuation) = AsyncStream<[TelegramEvent]>.makeStream(
            // Buffer rather than drop: losing an update would desynchronise
            // state, which is worse than briefly using more memory.
            bufferingPolicy: .unbounded
        )
        let cache = ChatCache()
        let emitter = EventEmitter(continuation: continuation)
        self.events = stream
        self.emitter = emitter
        self.cache = cache

        self.client = Self.sharedManager.createClient { data, _ in
            // Invoked on TDLibKit's per-client serial queue — already ordered.
            Self.handle(data: data, cache: cache, emitter: emitter)
        }
    }

    // MARK: - Lifecycle

    /// Sends `setTdlibParameters`, without which every account request fails
    /// with error 400 (verified; see ARCHITECTURE.md §1.2).
    public func initialize(
        credentials: TelegramCredentials,
        databaseDirectory: URL,
        filesDirectory: URL
    ) async throws(DomainError) {
        try await run {
            _ = try await self.client.setTdlibParameters(
                apiHash: credentials.apiHash,
                apiId: credentials.apiID,
                applicationVersion: Self.applicationVersion,
                databaseDirectory: databaseDirectory.path,
                databaseEncryptionKey: Data(),
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
                chatList: list == .main ? .chatListMain : .chatListArchive,
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

    public func sendText(_ text: String, to chat: ChatID) async throws(DomainError) {
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
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil
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
        emitter: EventEmitter
    ) {
        // Responses to requests carry "@extra" and are routed by TDLibKit before
        // reaching here; anything that fails to decode is not an update we model.
        guard let update = try? decodeUpdate(data) else { return }

        switch update {
        case .updateAuthorizationState(let u):
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
    private func run<T>(_ body: () async throws -> T) async throws(DomainError) -> T {
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
    public func prepareRange(fileID: Int, offset: Int64, length: Int64) async throws {
        guard length > 0 else { return }
        for _ in 0..<60 {
            try Task.checkCancellation()
            let available = try await client.getFileDownloadedPrefixSize(fileId: fileID, offset: offset).size
            if available >= length { return }
            _ = try await client.downloadFile(
                fileId: fileID, limit: length, offset: offset, priority: 32, synchronous: true)
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
