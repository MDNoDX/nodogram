//  AppModel — the presentation-layer owner of app state.
//
//  It is the single consumer of the gateway's ordered event stream. TDLib's
//  contract requires updates be applied in the order received, so there is
//  exactly one consuming task here, never a parallel fan-out
//  (Documentation/ARCHITECTURE.md §5).
//
//  @MainActor because everything it publishes drives SwiftUI directly. The
//  gateway it calls into is Sendable-by-contract, so crossing into it is safe.

import CryptoKit
import Foundation
import Observation
import OSLog
import NodogramDomain
import NodogramTelegram
import NodogramCore
import NodogramPlatform

/// Diagnostics: counts, states and timings only. Never message text, names or
/// phone numbers — logs leave the app's privacy boundary (SECURITY_MODEL.md §3).
private let log = Logger(subsystem: "app.nodogram", category: "sync")

@MainActor
@Observable
public final class AppModel {

    /// What the window shows. Derived from credentials and authorization state
    /// rather than set imperatively, so the UI cannot disagree with reality.
    public enum Phase: Equatable {
        case loadingCredentials
        case needsCredentials(detail: String?)
        case authenticating(AuthorizationState)
        case ready
        /// The Keychain would not hand over the database key. Nothing is
        /// lost; the user approves access and tries again.
        case storageLocked(detail: String)
    }

    // MARK: Session

    public private(set) var phase: Phase = .loadingCredentials
    public private(set) var connectionState: ConnectionState = .connecting
    public private(set) var tdlibVersion: String?
    public private(set) var authErrorMessage: String?
    public private(set) var isBusy = false

    // MARK: Chat list

    public private(set) var chatsByID: [ChatID: Chat] = [:]
    public private(set) var isLoadingChats = false
    public private(set) var myUserID: UserID?
    public var selectedDestination: SidebarDestination = .allChats {
        didSet {
            selectedFolderID = nil
            if selectedDestination == .archived { loadMoreChats(in: .archive) }
        }
    }
    /// The user's Telegram chat folders, in their order.
    public internal(set) var folders: [ChatFolderSummary] = []
    /// A Telegram folder shown in the chat list, when one is selected.
    public internal(set) var selectedFolderID: Int?
    /// The page open in Settings (shown in the window, like Telegram's).
    public var settingsPage: SettingsPage = .profile
    /// Sidebar items the user hid, and the order of the built-in ones.
    public internal(set) var sidebarPrefs = SidebarPrefs.load()
    public var searchText: String = ""

    // MARK: Conversation

    public private(set) var selectedChatID: ChatID?
    public internal(set) var messages: [Message] = []
    public internal(set) var isLoadingHistory = false
    public internal(set) var hasMoreHistory = true
    public internal(set) var conversationError: String?

    // MARK: Media

    /// Live download progress, observed per file.
    public let files = FileStore()
    /// The message whose media is open in the full-window viewer.
    public var viewerMessageID: MessageID?

    /// A short, self-dismissing confirmation ("Saved to Downloads").
    public private(set) var toast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    public func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Conversation extras

    /// What the composer is doing besides plain typing.
    public enum ComposerMode: Equatable {
        case normal
        case replying(Message)
        case editing(Message)
    }
    public var composerMode: ComposerMode = .normal

    /// Multi-select ("Select" in the context menu).
    public var isSelecting = false
    public var selectedMessageIDs: Set<MessageID> = []

    /// Messages waiting for the user to pick where to forward them.
    public var forwardRequest: ForwardRequest?

    /// Briefly highlighted after a jump (reply tap, search result).
    public var highlightedMessageID: MessageID?
    /// True after jumping into older history: newer messages are not loaded.
    public internal(set) var hasNewerHistory = false

    /// Official sponsored messages for the open channel (API terms 3.3).
    public internal(set) var sponsored: [SponsoredItem] = []
    @ObservationIgnored var sponsoredFetchedAt: [ChatID: Date] = [:]
    @ObservationIgnored var sponsoredViewed: Set<MessageID> = []

    /// Comment thread of a channel post, shown in a side panel.
    public internal(set) var comments: CommentsState?

    /// Quotes for replies whose original is not among loaded messages.
    public internal(set) var replyPreviews: [MessageID: ReplyPreview] = [:]
    @ObservationIgnored var requestedReplies: Set<MessageID> = []

    /// Still images for custom-emoji reactions, by custom emoji id.
    public internal(set) var customEmoji: [Int64: String] = [:]
    @ObservationIgnored var requestedCustomEmoji: Set<Int64> = []

    /// Chats that currently have stories, for the strip above the chat list.
    public internal(set) var storyOwners: [ChatID: StoryOwner] = [:]
    public var storyViewer: StoryViewerState?

    /// Reactions the open chat allows, for the right-click reaction row.
    public internal(set) var chatReactions: [ReactionSummary.Kind] = []

    /// In-conversation search (⌘F).
    public var conversationSearch: ConversationSearchState?
    /// ⌘K palette.
    public var isPaletteVisible = false

    // MARK: Activity

    /// Who is typing / recording where, with when it was last renewed.
    /// Telegram renews these every few seconds; stale ones are pruned.
    public private(set) var activities: [ChatID: [UserID: (activity: ChatActivity, at: Date)]] = [:]

    // MARK: Composer

    public var draftText: String = ""
    public internal(set) var draftIndicatorVisible = false

    // MARK: Private

    var gateway: TelegramGateway?
    private var eventTask: Task<Void, Never>?
    private var draftSaveTask: Task<Void, Never>?
    private var exhaustedLists: Set<ChatListKind> = []
    private var requestedAvatars: Set<ChatID> = []
    private var requestedReadDates: Set<MessageID> = []
    private var didStartChatSync = false
    var archive: MessageArchive?
    /// Set while a jump into another chat loads the history around its
    /// target, so the chat's default "latest page" load does not replace it.
    var pendingJumpID: MessageID?
    var archiveDirectory: URL?
    /// Messages the user deleted from this Mac ("chat-message"); their
    /// deletion is the user's own and leaves nothing behind.
    var selfDeletedKeys: Set<String> = []
    /// The one Keychain-held key; TDLib's and the archive's keys derive from it.
    var masterKey: SymmetricKey?
    /// Who started typing to the user, when, and whether they sent anything.
    public internal(set) var typingLog: [TypingEvent] = TypingEvent.loadAll()
    public internal(set) var unseenTypingCount = 0
    /// Messages others deleted since the user last looked at the Deleted section.
    public internal(set) var unseenDeletedCount = 0
    /// Everyone who viewed the user's stories, kept after Telegram forgets.
    public internal(set) var storyViewers: [StoryViewer] = StoryViewersStore.load()
    var openTypingSessions: [String: UUID] = [:]
    var typingNotifiedAt: [ChatID: Date] = [:]
    var typingSweepTask: Task<Void, Never>?
    var storyPollTask: Task<Void, Never>?
    /// Messages the user starred, newest first. Local to this Mac.
    public var starred: [StarredMessage] = StarredMessage.loadAll()
    /// Chats opened recently, newest first — the Recently Viewed section.
    public var recentChatIDs: [ChatID] = (UserDefaults.standard.array(forKey: "recentlyViewed.chats") as? [Int64] ?? [])
        .map { ChatID($0) }
    private var activityPruneTask: Task<Void, Never>?

    public init() {}

    // MARK: - Derived state

    /// Destinations that are real chat lists. The rest are later phases and
    /// say so, rather than showing an unrelated list.
    public var destinationIsChatList: Bool {
        selectedFolderID != nil || filter(for: selectedDestination) != nil || selectedDestination == .saved
    }

    public var visibleChats: [Chat] {
        if let folderID = selectedFolderID { return chats(inFolder: folderID) }
        if selectedDestination == .saved {
            guard let me = myUserID, let saved = chatsByID[ChatID(me.rawValue)] else { return [] }
            return [saved]
        }
        guard let filter = filter(for: selectedDestination) else { return [] }
        return ChatListQuery.visibleChats(chatsByID.values, filter: filter, search: searchText)
    }

    public var unreadTotal: Int { ChatListQuery.unreadTotal(chatsByID.values) }

    public var draftCount: Int {
        chatsByID.values.filter { $0.order != 0 && $0.hasDraft }.count
    }

    public var selectedChat: Chat? { selectedChatID.flatMap { chatsByID[$0] } }

    private func filter(for destination: SidebarDestination) -> ChatListFilter? {
        switch destination {
        case .allChats: return .all
        case .unread: return .unread
        case .personal: return .personal
        case .groups: return .groups
        case .channels: return .channels
        case .archived: return .archived
        case .drafts: return .drafts
        default: return nil
        }
    }

    // MARK: - Startup

    /// Loads credentials and, if present, starts TDLib. Safe to call again from
    /// the setup screen's "Check Again" button.
    public func start() async {
        eventTask?.cancel()
        gateway?.shutdown()
        gateway = nil

        switch TelegramCredentials.fromBundle() {
        case .failure(let error):
            phase = .needsCredentials(detail: error.technicalDetail)
        case .success(let credentials):
            await startTelegram(with: credentials)
        }
    }

    private func startTelegram(with credentials: TelegramCredentials) async {
        let gateway = TelegramGateway()
        self.gateway = gateway

        // One task, consuming in order. This is the ordering guarantee.
        eventTask = Task { [weak self] in
            for await batch in gateway.events {
                guard let self else { return }
                for event in batch { self.apply(event) }
            }
        }

        do {
            let directories = try Self.accountDirectories()
            guard loadMasterKey() else { return }
            openArchive(in: directories.root)
            try await initializeEncrypted(gateway, credentials: credentials, directories: directories)
            connectNotifications()
            tdlibVersion = try? await gateway.tdlibVersion()

            // Ask for the current state rather than relying on an update that may
            // have been emitted before the stream was consumed.
            if let state = try await gateway.currentAuthorizationState() {
                applyAuthorizationState(state)
            }
        } catch DomainError.notAuthorized where masterKey != nil
                    && UserDefaults.standard.bool(forKey: "tdlib.databaseEncrypted.default") {
            // TDLib's answer to a database key that doesn't match. The session
            // is intact; never present this as "signed out".
            phase = .storageLocked(detail: "The database key from the Keychain doesn't match the saved session.")
        } catch let error as DomainError {
            // `.notInitialized` is transient, not a failure to show.
            if error != .notInitialized {
                authErrorMessage = error.userFacingDescription
            }
        } catch {
            authErrorMessage = DomainError.protocolFailure(code: -1, message: "\(error)").userFacingDescription
        }
    }

    // MARK: - Event application

    private func apply(_ event: TelegramEvent) {
        switch event {
        case .authorizationStateChanged(let state):
            applyAuthorizationState(state)

        case .connectionStateChanged(let state):
            connectionState = state

        case .optionReceived(let name, let value):
            if name == "version" { tdlibVersion = value }

        case .chatUpdated(let chat):
            chatsByID[chat.id] = chat
            refreshBadge()

        case .chatAvatarReady(let chatID, let path):
            chatsByID[chatID]?.avatarPath = path

        case .messageAdded(let message):
            record([message])
            noteMessageForTyping(message)
            checkKeywords(message)
            appendToCommentsIfNeeded(message)
            guard message.chatID == selectedChatID,
                  !messages.contains(where: { $0.id == message.id }) else { return }
            insertSorted(message)
            if !message.isOutgoing, !message.isService {
                markVisibleAsRead([message.id])
            }

        case .messageReplaced(let old, let new):
            record([new])
            guard new.chatID == selectedChatID else { return }
            if let index = messages.firstIndex(where: { $0.id == old }) {
                messages[index] = new
                messages.sort { $0.id.rawValue < $1.id.rawValue }
            } else if !messages.contains(where: { $0.id == new.id }) {
                insertSorted(new)
            }

        case .messagesDeleted(let chatID, let ids):
            handleDeletion(chatID: chatID, ids: ids)

        case .messageContentChanged(let chatID, let messageID, let text, let label):
            if keepsDeletedMessages, let archive {
                Task.detached { await archive.recordEdit(chatID: chatID, messageID: messageID, text: text) }
            }
            guard chatID == selectedChatID,
                  let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].text = text
            messages[index].attachmentLabel = label

        case .messageEdited(let chatID, let messageID, let editDate):
            guard chatID == selectedChatID,
                  let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].editDate = editDate

        case .fileUpdated(let file):
            files.apply(file)

        case .messageInteraction(let chatID, let messageID, let views, let forwards, let reactions, let comments):
            applyInteraction(chatID: chatID, messageID: messageID, views: views, forwards: forwards,
                             reactions: reactions, comments: comments)

        case .storiesChanged(let owner):
            if owner.storyIDs.isEmpty { storyOwners.removeValue(forKey: owner.chatID) }
            else { storyOwners[owner.chatID] = owner }

        case .notificationsAdded(let notifications):
            deliverNotifications(notifications)

        case .notificationsRemoved(let groupID, let ids):
            SystemNotifications.shared.remove(groupID: groupID, ids: ids)

        case .foldersChanged(let folders, _):
            self.folders = folders
            if let id = selectedFolderID, !folders.contains(where: { $0.id == id }) { selectedFolderID = nil }

        case .pollUpdated(let poll):
            for index in messages.indices where messages[index].poll?.id == poll.id {
                let details = messages[index].poll?.details ?? ""
                messages[index].poll = PollContent(
                    id: poll.id, question: poll.question, questionEntities: poll.questionEntities,
                    details: details, options: poll.options, totalVoters: poll.totalVoters,
                    isAnonymous: poll.isAnonymous, allowsMultipleAnswers: poll.allowsMultipleAnswers,
                    allowsRevoting: poll.allowsRevoting, canSeeResults: poll.canSeeResults,
                    isClosed: poll.isClosed, closeDate: poll.closeDate, kind: poll.kind,
                    restriction: poll.restriction)
            }

        case .chatActivity(let chatID, let user, let activity):
            noteTyping(chatID: chatID, user: user, activity: activity)
            if let activity {
                activities[chatID, default: [:]][user] = (activity, Date())
                scheduleActivityPrune()
            } else {
                activities[chatID]?.removeValue(forKey: user)
                if activities[chatID]?.isEmpty == true { activities.removeValue(forKey: chatID) }
            }

        case .outboxRead(let chatID, let upTo):
            guard chatID == selectedChatID else { return }
            for index in messages.indices
            where messages[index].isOutgoing && messages[index].id.rawValue <= upTo.rawValue {
                messages[index].isReadByRecipient = true
            }
        }
    }

    private func applyAuthorizationState(_ state: AuthorizationState) {
        // A locked key leaves TDLib waiting for parameters; that is not a
        // sign-out, so keep the explanation on screen until "Try Again".
        if case .storageLocked = phase, state != .ready { return }
        switch state {
        case .ready:
            phase = .ready
            authErrorMessage = nil
            startChatSync()
        case .closed, .loggingOut, .closing:
            phase = .authenticating(.waitingForPhoneNumber)
            resetSessionState()
        default:
            // Keep `.ready` sticky against a late `waitingForParameters`, which
            // would otherwise bounce a signed-in user back to the login screen.
            if case .ready = phase, state == .waitingForParameters { return }
            phase = .authenticating(state)
        }
    }

    private func resetSessionState() {
        chatsByID = [:]
        messages = []
        selectedChatID = nil
        myUserID = nil
        exhaustedLists = []
        requestedAvatars = []
        requestedReadDates = []
        didStartChatSync = false
        activities = [:]
        viewerMessageID = nil
    }

    // MARK: - Chat list

    private func startChatSync() {
        guard !didStartChatSync, let gateway else { return }
        didStartChatSync = true
        loadMoreChats(in: .main)
        Task { await gateway.enableNotifications() }
        Task { await gateway.loadStories() }
        startStoryViewerPolling()

        Task { [weak self] in
            guard let me = try? await gateway.myUserID() else { return }
            self?.myUserID = me
            // "Saved" must work even when Saved Messages is not among the
            // chats loaded so far.
            await gateway.ensurePrivateChat(with: me)

            // Diagnostic: `--args -NodogramPollProbe YES` logs the structure of
            // recent real polls — counts and flags only, never text.
            if UserDefaults.standard.bool(forKey: "NodogramPollProbe") {
                try? await Task.sleep(for: .seconds(4))   // let the chat list load
                var polls: [Message] = []
                let candidates = self?.chatsByID.values.filter { chat in
                    switch chat.kind {
                    case .basicGroup, .supergroup, .channel: return chat.order != 0
                    default: return false
                    }
                } ?? []
                for chat in candidates.prefix(60) where polls.count < 25 {
                    polls += (try? await gateway.polls(in: chat.id, limit: 3)) ?? []
                }
                log.info("poll probe: chats=\(candidates.prefix(60).count) found=\(polls.count) mapped=\(polls.filter { $0.poll != nil }.count)")
                for message in polls {
                    guard let poll = message.poll else {
                        log.info("poll probe UNMAPPED label=\(message.attachmentLabel ?? "nil", privacy: .public)")
                        continue
                    }
                    log.info("""
                        poll options=\(poll.options.count) voters=\(poll.totalVoters) quiz=\(poll.isQuiz) \
                        multi=\(poll.allowsMultipleAnswers) voted=\(poll.hasVoted) closed=\(poll.isClosed) \
                        canSeeResults=\(poll.canSeeResults) showsResults=\(poll.showsResults) \
                        pctSum=\(poll.options.map(\.percentage).reduce(0, +)) restricted=\(poll.restriction != nil) \
                        emptyOptionText=\(poll.options.contains { $0.text.isEmpty }) hasQuestion=\(!poll.question.isEmpty)
                        """)
                }
            }

            // Developer convenience for verifying the conversation view without
            // UI automation: `open Nodogram.app --args -NodogramOpenSavedOnLaunch YES`.
            // Launch arguments are volatile, so nothing persists between runs.
            if UserDefaults.standard.bool(forKey: "NodogramOpenSavedOnLaunch") {
                self?.selectedDestination = .saved
                self?.select(ChatID(me.rawValue))
            }
        }
    }

    /// Asks TDLib for more chats. They arrive as events; this only drives
    /// paging and stops once TDLib says the list is complete.
    public func loadMoreChats(in list: ChatListKind = .main) {
        guard let gateway, !isLoadingChats, !exhaustedLists.contains(list) else { return }
        isLoadingChats = true
        Task { [weak self] in
            let hasMore = (try? await gateway.loadChats(list, limit: 100)) ?? false
            guard let self else { return }
            if !hasMore { self.exhaustedLists.insert(list) }
            self.isLoadingChats = false
        }
    }

    /// Called as rows scroll into view, so only visible avatars are downloaded.
    public func ensureAvatar(for chatID: ChatID) {
        guard let gateway, chatsByID[chatID]?.avatarPath == nil,
              requestedAvatars.insert(chatID).inserted else { return }
        Task { await gateway.ensureAvatar(chatID) }
    }

    // MARK: - Conversation

    public func select(_ chatID: ChatID?) {
        log.debug("select requested chat=\(chatID?.rawValue ?? 0, privacy: .private) current=\(self.selectedChatID?.rawValue ?? 0, privacy: .private)")
        guard chatID != selectedChatID else { return }

        // Flush the outgoing chat's draft immediately; this is the save that
        // matters most, because switching chats is how drafts usually get lost.
        if let previous = selectedChatID, let gateway {
            draftSaveTask?.cancel()
            let text = draftText
            if text != (chatsByID[previous]?.draftText ?? "") {
                Task { await gateway.setDraft(text, chat: previous) }
            }
            Task { await gateway.closeChat(previous) }
        }

        selectedChatID = chatID
        pendingJumpID = nil
        if let chatID { noteRecentlyViewed(chatID) }
        messages = []
        hasMoreHistory = true
        hasNewerHistory = false
        composerMode = .normal
        endSelection()
        sponsored = []
        chatReactions = []
        comments = nil
        conversationSearch = nil
        highlightedMessageID = nil
        if let chatID { SystemNotifications.shared.removeAll(forChat: chatID.rawValue) }
        conversationError = nil
        draftIndicatorVisible = false
        requestedReadDates = []
        draftText = chatID.flatMap { chatsByID[$0]?.draftText } ?? ""

        guard let chatID, let gateway else { return }
        log.info("select chat=\(chatID.rawValue, privacy: .private) known=\(self.chatsByID[chatID] != nil)")
        isLoadingHistory = true
        Task { [weak self] in
            await gateway.openChat(chatID)
            do {
                let loaded = try await gateway.history(chatID, before: nil, limit: 50)
                log.info("history loaded count=\(loaded.count) stillSelected=\(self?.selectedChatID == chatID)")
                guard let self, self.selectedChatID == chatID else { return }
                self.record(loaded)
                self.loadSponsored(for: chatID)
                // A jump is loading a different part of the history.
                guard self.pendingJumpID == nil else { return }
                self.messages = await self.mergingDeleted(into: loaded, chatID: chatID, openEnded: true)
                self.hasMoreHistory = !loaded.isEmpty
                if let newest = loaded.last(where: { !$0.isService }) {
                    self.chatReactions = await self.availableReactions(for: newest)
                }
                self.markVisibleAsRead(loaded.filter { !$0.isOutgoing }.suffix(50).map(\.id))
            } catch {
                log.error("history failed: \(String(describing: error), privacy: .public)")
                guard let self, self.selectedChatID == chatID else { return }
                self.conversationError = Self.describe(error)
            }
            self?.isLoadingHistory = false
        }
    }

    private func noteRecentlyViewed(_ chatID: ChatID) {
        recentChatIDs.removeAll { $0 == chatID }
        recentChatIDs.insert(chatID, at: 0)
        if recentChatIDs.count > 40 { recentChatIDs.removeLast(recentChatIDs.count - 40) }
        UserDefaults.standard.set(recentChatIDs.map(\.rawValue), forKey: "recentlyViewed.chats")
    }

    public func clearRecentlyViewed() {
        recentChatIDs = []
        UserDefaults.standard.removeObject(forKey: "recentlyViewed.chats")
    }

    /// Loads older messages when the user scrolls to the top.
    public func loadOlderMessages() {
        guard let gateway, let chatID = selectedChatID, !isLoadingHistory, hasMoreHistory,
              let oldest = messages.first else { return }
        isLoadingHistory = true
        Task { [weak self] in
            let older = (try? await gateway.history(chatID, before: oldest.id, limit: 50)) ?? []
            guard let self, self.selectedChatID == chatID else { return }
            self.record(older)
            let known = Set(self.messages.map(\.id))
            let fresh = older.filter { !known.contains($0.id) }
            let withDeleted = await self.mergingDeleted(into: fresh, chatID: chatID, openEnded: false)
                .filter { !known.contains($0.id) }
            self.messages = (withDeleted + self.messages).sorted { $0.id.rawValue < $1.id.rawValue }
            self.hasMoreHistory = !fresh.isEmpty
            self.isLoadingHistory = false
        }
    }

    /// Fetches the exact read time for an outgoing message as it comes into
    /// view. Only private chats support this; in groups Telegram offers a
    /// read-by list instead, so nothing is requested there.
    public func ensureReadDate(for message: Message) {
        guard let gateway, message.isOutgoing, message.isReadByRecipient, message.readDate == nil,
              let chat = chatsByID[message.chatID], case .privateChat = chat.kind,
              requestedReadDates.insert(message.id).inserted else { return }
        Task { [weak self] in
            guard let readDate = await gateway.readDate(message.chatID, message: message.id),
                  let self,
                  let index = self.messages.firstIndex(where: { $0.id == message.id }) else { return }
            self.messages[index].readDate = readDate
        }
    }

    func markVisibleAsRead(_ ids: [MessageID]) {
        guard let gateway, let chatID = selectedChatID, !ids.isEmpty else { return }
        Task { await gateway.markRead(chatID, messages: ids) }
    }

    func insertSorted(_ message: Message) {
        let index = messages.firstIndex { $0.id.rawValue > message.id.rawValue } ?? messages.endIndex
        messages.insert(message, at: index)
    }

    // MARK: - Deleted-message archive

    /// Whether messages deleted by their sender are kept and shown in place.
    /// On unless the user turned it off in Settings → Privacy.
    public static let keepDeletedKey = "privacy.keepDeletedMessages"
    public static let deletedRetentionKey = "privacy.deletedRetentionDays"

    /// On by default at the user's request (Documentation/DECISIONS.md D15);
    /// Settings → Nodogram Features turns it off. Self-destructing and
    /// protected content is never kept either way.
    var keepsDeletedMessages: Bool {
        UserDefaults.standard.object(forKey: Self.keepDeletedKey) as? Bool ?? true
    }

    /// Opens the archive only when it is switched on: its key lives in the
    /// Keychain, and reading it for a feature that is off would cost the user
    /// a Keychain prompt for nothing.
    func openArchive(in directory: URL) {
        archiveDirectory = directory
        guard archive == nil else { return }
        guard keepsDeletedMessages else {
            // Old archives are erased without the key: deleting the files is enough.
            if !UserDefaults.standard.bool(forKey: "archive.complianceErase.v1") {
                UserDefaults.standard.set(true, forKey: "archive.complianceErase.v1")
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent("archive.sqlite" + suffix))
                }
            }
            return
        }
        guard let master = masterKey else { return }
        // Archives made before the key was derived from the master key cannot
        // be read with it; they held at most a few hours, and are cleared once.
        if !UserDefaults.standard.bool(forKey: "archive.derivedKey.v1") {
            UserDefaults.standard.set(true, forKey: "archive.derivedKey.v1")
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("archive.sqlite" + suffix))
            }
        }
        do {
            let archive = try MessageArchive.shared(directory: directory,
                                                    key: KeychainKey.derive(from: master, purpose: "message-archive"))
            self.archive = archive
            // One-time: archives made before the compliance fix may hold
            // self-destructing or protected content. They cannot be told apart
            // after the fact, so they are erased once.
            if !UserDefaults.standard.bool(forKey: "archive.complianceErase.v1") {
                UserDefaults.standard.set(true, forKey: "archive.complianceErase.v1")
                Task.detached { await archive.eraseAll() }
            }
            let days = UserDefaults.standard.object(forKey: Self.deletedRetentionKey) as? Int ?? 365
            Task.detached {
                // Ordinary messages are kept 90 days — long enough to catch a
                // late "delete for everyone", short enough to stay small.
                await archive.applyRetention(
                    keepReceived: 90 * 86_400,
                    keepDeleted: days <= 0 ? nil : TimeInterval(days) * 86_400)
            }
        } catch {
            log.error("archive unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    /// Records received messages for the deleted-message archive. Never
    /// self-destructing or auto-deleting content (API terms 1.4), and never
    /// content the sender protected from saving.
    func record(_ messages: [Message]) {
        guard keepsDeletedMessages else { return }
        if archive == nil, let archiveDirectory { openArchive(in: archiveDirectory) }
        guard let archive else { return }
        let eligible = messages.filter { !$0.isEphemeral && $0.canBeSaved }
        guard !eligible.isEmpty else { return }
        Task.detached { await archive.record(eligible) }
    }

    /// Replaces deleted messages with their archived copies, marked deleted.
    /// Without an archived copy (never received here), they are removed — the
    /// app does not invent a placeholder for something it never saw.
    private func handleDeletion(chatID: ChatID, ids: [MessageID]) {
        let removed = Set(ids)
        if keepsDeletedMessages, archive == nil, let archiveDirectory { openArchive(in: archiveDirectory) }
        guard keepsDeletedMessages, let archive else {
            if chatID == selectedChatID { messages.removeAll { removed.contains($0.id) } }
            return
        }
        // Deletions the user made here, or of their own messages anywhere,
        // are theirs: those messages simply go.
        let mine = Set(ids.filter { selfDeletedKeys.remove("\(chatID.rawValue)-\($0.rawValue)") != nil })
        Task { [weak self] in
            await archive.forget(chatID: chatID, messageIDs: Array(mine))
            let candidates = ids.filter { !mine.contains($0) }
            let marked = await archive.markDeleted(chatID: chatID, messageIDs: candidates)
            let ownCopies = marked.filter(\.isOutgoing).map(\.id)
            await archive.forget(chatID: chatID, messageIDs: ownCopies)
            let archived = marked.filter { !$0.isOutgoing }
            guard let self else { return }
            self.announceDeleted(archived.filter { !$0.isService }, in: chatID)
            guard chatID == self.selectedChatID else { return }
            let byID = Dictionary(uniqueKeysWithValues: archived.map { ($0.id, $0) })
            self.messages = self.messages.compactMap { message in
                guard removed.contains(message.id) else { return message }
                guard var copy = byID[message.id] else { return nil }
                // Keep the media the chat was already showing: a photo seen
                // before deletion stays visible (from cache or its preview).
                copy.media = message.media
                copy.albumID = 0
                return copy
            }
        }
    }

    /// Adds archived deleted messages that fall inside a page of history.
    func mergingDeleted(into page: [Message], chatID: ChatID, openEnded: Bool) async -> [Message] {
        guard keepsDeletedMessages, let archive, let first = page.first, let last = page.last else { return page }
        let upper = openEnded ? Int64.max : last.id.rawValue
        let deleted = await archive.deletedMessages(in: chatID, ids: first.id.rawValue...upper)
        guard !deleted.isEmpty else { return page }
        let known = Set(page.map(\.id))
        return (page + deleted.filter { !known.contains($0.id) }).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    // MARK: - Activity

    /// "typing…" for a chat header or row, or nil.
    public func activityText(for chatID: ChatID) -> String? {
        guard let entries = activities[chatID], !entries.isEmpty else { return nil }
        let isGroup: Bool = {
            switch chatsByID[chatID]?.kind {
            case .basicGroup, .supergroup: return true
            default: return false
            }
        }()
        let latest = entries.max { $0.value.at < $1.value.at }!.value.activity
        guard isGroup else { return "\(latest.phrase)…" }
        if entries.count > 1 { return "\(entries.count) people are \(latest == .typing ? "typing" : "busy")…" }
        return "someone is \(latest.phrase)…"
    }

    private func scheduleActivityPrune() {
        guard activityPruneTask == nil else { return }
        activityPruneTask = Task { [weak self] in
            while let self, !self.activities.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                // Telegram renews an action roughly every 5 s; 6 s of silence
                // means it ended without an explicit cancel.
                let cutoff = Date().addingTimeInterval(-6)
                for (chat, users) in self.activities {
                    let fresh = users.filter { $0.value.at > cutoff }
                    self.activities[chat] = fresh.isEmpty ? nil : fresh
                }
            }
            self?.activityPruneTask = nil
        }
    }

    // MARK: - Media

    /// Bytes for streaming playback, served by the gateway.
    public var byteSource: MediaByteSource? { gateway }

    /// Starts a download; progress arrives through `files`.
    public func download(_ file: MediaFile, priority: Int = 8) {
        guard let gateway, !file.isComplete else { return }
        Task { await gateway.startDownload(file.id, priority: priority) }
    }

    /// Downloads and waits — for small files the UI needs right away.
    public func fetch(_ file: MediaFile, priority: Int = 16) async -> MediaFile? {
        if let current = files.current(file.id), current.isComplete { return current }
        if file.isComplete { return file }
        guard let gateway, let result = await gateway.downloadAndWait(file.id, priority: priority) else { return nil }
        files.apply(result)
        return result
    }

    public func cancelDownload(_ file: MediaFile) {
        guard let gateway else { return }
        Task { await gateway.cancelDownload(file.id) }
    }

    /// Messages in the open chat that the viewer can page through.
    public var viewableMedia: [Message] {
        messages.filter { message in
            guard !message.isDeleted, let media = message.media else { return false }
            switch media {
            case .photo, .video, .animation: return true
            default: return false
            }
        }
    }

    public func openViewer(_ message: Message) {
        viewerMessageID = message.id
    }

    public func closeViewer() {
        viewerMessageID = nil
    }

    // MARK: - Polls

    /// Votes for the given Telegram option indexes. Telegram reflects the
    /// change back through `updatePoll` (first as "being chosen"), so nothing
    /// is faked locally.
    public func vote(_ options: [Int], in message: Message) {
        guard let gateway, !options.isEmpty else { return }
        Task { [weak self] in
            do {
                try await gateway.vote(options, on: message.id, in: message.chatID)
            } catch {
                self?.showToast(Self.describe(error))
            }
        }
    }

    public func retractVote(in message: Message) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                try await gateway.vote([], on: message.id, in: message.chatID)
            } catch {
                self?.showToast(Self.describe(error))
            }
        }
    }

    // MARK: - Composer

    /// Debounced save of the composer text as the chat's Telegram draft, so it
    /// survives restarts. "Draft saved" appears only after a save really ran.
    public func draftTextChanged() {
        draftSaveTask?.cancel()
        guard let gateway, let chatID = selectedChatID else { return }
        let text = draftText
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await gateway.setDraft(text, chat: chatID)
            guard !Task.isCancelled, let self else { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.draftIndicatorVisible = false
                return
            }
            self.draftIndicatorVisible = true
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.draftIndicatorVisible = false
        }
    }

    public func sendDraft() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let gateway, let chatID = selectedChatID else { return }

        draftSaveTask?.cancel()
        draftText = ""
        draftIndicatorVisible = false
        Task { [weak self] in
            do {
                // Sending with `clearDraft` also clears the Telegram draft.
                try await gateway.sendText(text, to: chatID)
            } catch {
                guard let self else { return }
                // Put the text back: a failed send must never cost the user
                // what they wrote.
                if self.selectedChatID == chatID, self.draftText.isEmpty { self.draftText = text }
                self.conversationError = Self.describe(error)
            }
        }
    }

    /// Typed throws do not survive inference through a `Task` closure, so the
    /// caught error is `any Error` even though the gateway only throws
    /// `DomainError`; this narrows it without a force cast.
    static func describe(_ error: any Error) -> String {
        (error as? DomainError)?.userFacingDescription
            ?? DomainError.protocolFailure(code: -1, message: "\(error)").userFacingDescription
    }

    public func dismissConversationError() {
        conversationError = nil
    }

    // MARK: - Authentication actions

    public func submitPhoneNumber(_ phoneNumber: String) {
        performAuthStep { gateway in try await gateway.setPhoneNumber(phoneNumber) }
    }

    public func submitCode(_ code: String) {
        performAuthStep { gateway in try await gateway.checkCode(code) }
    }

    public func submitPassword(_ password: String) {
        performAuthStep { gateway in try await gateway.checkPassword(password) }
    }

    public func signOut() {
        performAuthStep { gateway in try await gateway.logOut() }
    }

    private func performAuthStep(
        _ body: @escaping @Sendable (TelegramGateway) async throws -> Void
    ) {
        guard let gateway else { return }
        authErrorMessage = nil
        isBusy = true
        Task { [weak self] in
            do {
                try await body(gateway)
            } catch let error as DomainError {
                self?.authErrorMessage = error.userFacingDescription
            } catch {
                self?.authErrorMessage = DomainError
                    .protocolFailure(code: -1, message: "\(error)")
                    .userFacingDescription
            }
            self?.isBusy = false
        }
    }

    // MARK: - Shutdown

    /// Called from `willTerminate`. TDLib requires clients be closed before
    /// termination to keep its database consistent.
    public func shutdown() {
        draftSaveTask?.cancel()
        eventTask?.cancel()
        gateway?.shutdown()
        gateway = nil
    }

    // MARK: - Database encryption

    /// TDLib's database is encrypted with a random key kept in the Keychain.
    ///
    /// Databases created before this existed are unencrypted. They are opened
    /// with the empty key once, re-encrypted with `setDatabaseEncryptionKey`,
    /// and only after TDLib confirms success is that recorded — so a failure
    /// at any step leaves a working (if unencrypted) database rather than a
    /// locked-out user.
    /// Reads the master key once per launch. Returns false — and shows why —
    /// when the session database is encrypted and the key cannot be read:
    /// opening it without the key would look like a sign-out.
    private func loadMasterKey() -> Bool {
        if masterKey != nil { return true }
        do {
            masterKey = try KeychainKey.loadOrCreate(service: "app.nodogram.tdlib", account: "default")
            return true
        } catch {
            log.error("master key unavailable: \(String(describing: error), privacy: .public)")
            if UserDefaults.standard.bool(forKey: "tdlib.databaseEncrypted.default") {
                phase = .storageLocked(detail: "Nodogram couldn't read its key from the Keychain (\(error)).")
                return false
            }
            // Never encrypted yet: carry on unencrypted, as before.
            return true
        }
    }

    private func initializeEncrypted(_ gateway: TelegramGateway, credentials: TelegramCredentials,
                                     directories: AccountDirectories) async throws {
        let migratedKey = "tdlib.databaseEncrypted.default"
        guard let master = masterKey else {
            try await gateway.initialize(credentials: credentials, databaseDirectory: directories.database,
                                         filesDirectory: directories.files)
            return
        }
        let key = master.withUnsafeBytes { Data($0) }

        let hasDatabase = FileManager.default.fileExists(atPath: directories.database.appendingPathComponent("db.sqlite").path)
        if UserDefaults.standard.bool(forKey: migratedKey) || !hasDatabase {
            try await gateway.initialize(credentials: credentials, databaseDirectory: directories.database,
                                         filesDirectory: directories.files, encryptionKey: key)
            UserDefaults.standard.set(true, forKey: migratedKey)
            return
        }

        // Existing unencrypted database: open it as it is, then re-encrypt.
        try await gateway.initialize(credentials: credentials, databaseDirectory: directories.database,
                                     filesDirectory: directories.files)
        do {
            try await gateway.setDatabaseKey(key)
            UserDefaults.standard.set(true, forKey: migratedKey)
            log.info("tdlib database re-encrypted")
        } catch {
            log.error("tdlib re-encryption failed, will retry next launch: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Storage layout

    struct AccountDirectories {
        let root: URL
        let database: URL
        let files: URL
    }

    static func accountDirectories() throws -> AccountDirectories {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let root = support
            .appendingPathComponent("Nodogram", isDirectory: true)
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("default", isDirectory: true)
        let database = root.appendingPathComponent("tdlib", isDirectory: true)
        let files = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        return AccountDirectories(root: root, database: database, files: files)
    }
}
