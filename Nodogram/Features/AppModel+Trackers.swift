//  Things Telegram shows only for a moment, kept so the user can look later:
//  who started typing (and whether they sent anything), messages others
//  deleted, and who viewed the user's stories.
//
//  All of it is data Telegram already delivers to this client. Nothing here
//  changes what other people see — no hidden read receipts, no fake status.

import AppKit
import Foundation
import NodogramDomain
import NodogramPlatform
import NodogramTelegram
import NodogramCore

// MARK: - Typing log model

public struct TypingEvent: Codable, Hashable, Identifiable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// Still typing, or just stopped — waiting to see if a message follows.
        case pending
        /// A message from them arrived.
        case sent
        /// They typed and then sent nothing.
        case abandoned
    }

    public let id: UUID
    public let chatID: Int64
    public let userID: Int64
    public var name: String
    public var chatTitle: String
    public var isGroup: Bool
    public var activity: String
    public let startedAt: Date
    public var lastSeenAt: Date
    public var endedAt: Date?
    public var outcome: Outcome
    public var messagePreview: String?

    public var duration: TimeInterval { (endedAt ?? lastSeenAt).timeIntervalSince(startedAt) }

    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Nodogram/typing-log.json")
    }()

    static func loadAll() -> [TypingEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([TypingEvent].self, from: data)) ?? []
    }

    static func saveAll(_ events: [TypingEvent]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(events) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

enum StoryViewersStore {
    static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Nodogram/story-viewers.json")
    }()

    static func load() -> [StoryViewer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([StoryViewer].self, from: data)) ?? []
    }

    static func save(_ viewers: [StoryViewer]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(viewers) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

/// User-facing switches for the trackers. All default on, as asked.
public enum TrackerSettings {
    public static let typingScopeKey = "typing.scope"            // "private" | "all" | "off"
    public static let typingNotifyKey = "typing.notify"          // Bool
    public static let typingAbandonedNotifyKey = "typing.notifyAbandoned"
    public static let deletedNotifyKey = "deleted.notify"
    public static let storyViewsNotifyKey = "stories.notifyViews"
    public static let keywordsKey = "alerts.keywords"            // comma-separated
    public static let streamerModeKey = "privacy.streamerMode"

    static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static var typingScope: String { UserDefaults.standard.string(forKey: typingScopeKey) ?? "private" }
}

extension AppModel {

    // MARK: - Typing

    private static let typingLogLimit = 2000
    /// Telegram repeats a typing action every ~5 s while it lasts.
    private static let typingTimeout: TimeInterval = 7
    /// How long after they stop typing a message still counts as "sent".
    private static let sendGrace: TimeInterval = 45

    func noteTyping(chatID: ChatID, user: UserID, activity: ChatActivity?) {
        let scope = TrackerSettings.typingScope
        guard scope != "off", let chat = chatsByID[chatID], user != myUserID, !chat.isBot else { return }
        let isGroup: Bool
        switch chat.kind {
        case .privateChat, .secret: isGroup = false
        case .basicGroup, .supergroup: isGroup = true
        case .channel: return
        }
        if isGroup, scope != "all" { return }

        let key = "\(chatID.rawValue)-\(user.rawValue)"
        let now = Date()
        guard let activity else {
            closeTyping(key: key, at: now)
            return
        }

        if let id = openTypingSessions[key], let index = typingLog.firstIndex(where: { $0.id == id }),
           now.timeIntervalSince(typingLog[index].lastSeenAt) < Self.typingTimeout {
            typingLog[index].lastSeenAt = now
            if activity != .typing { typingLog[index].activity = activity.phrase }
            return
        }

        let name = isGroup ? (gateway?.userName(user) ?? "Someone") : chat.title
        let event = TypingEvent(
            id: UUID(), chatID: chatID.rawValue, userID: user.rawValue, name: name, chatTitle: chat.title,
            isGroup: isGroup, activity: activity.phrase, startedAt: now, lastSeenAt: now, endedAt: nil,
            outcome: .pending, messagePreview: nil)
        typingLog.insert(event, at: 0)
        if typingLog.count > Self.typingLogLimit { typingLog.removeLast(typingLog.count - Self.typingLogLimit) }
        openTypingSessions[key] = event.id
        if selectedDestination != .typingLog { unseenTypingCount += 1 }
        notifyTyping(event, chat: chat)
        startTypingSweep()
        saveTypingLogSoon()
    }

    private func notifyTyping(_ event: TypingEvent, chat: Chat) {
        guard TrackerSettings.flag(TrackerSettings.typingNotifyKey), !chat.isMuted else { return }
        // Already looking at that chat: the header says "typing…".
        if NSApp.isActive, selectedChatID?.rawValue == event.chatID { return }
        let chatID = ChatID(event.chatID)
        if let last = typingNotifiedAt[chatID], Date().timeIntervalSince(last) < 120 { return }
        typingNotifiedAt[chatID] = Date()
        SystemNotifications.shared.post(.init(
            identifier: "typing-\(event.chatID)", chatID: event.chatID, messageID: 0,
            title: event.name, subtitle: event.isGroup ? event.chatTitle : "",
            body: "is \(event.activity)…", isSilent: true))
    }

    private func closeTyping(key: String, at date: Date) {
        guard let id = openTypingSessions.removeValue(forKey: key),
              let index = typingLog.firstIndex(where: { $0.id == id }) else { return }
        typingLog[index].endedAt = date
        let eventID = id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.sendGrace))
            self?.settleTyping(eventID)
        }
        saveTypingLogSoon()
    }

    /// No message arrived in time: they typed and thought better of it.
    private func settleTyping(_ id: UUID) {
        guard let index = typingLog.firstIndex(where: { $0.id == id }), typingLog[index].outcome == .pending else { return }
        typingLog[index].outcome = .abandoned
        let event = typingLog[index]
        saveTypingLogSoon()
        guard TrackerSettings.flag(TrackerSettings.typingAbandonedNotifyKey), event.duration >= 2,
              chatsByID[ChatID(event.chatID)]?.isMuted != true else { return }
        SystemNotifications.shared.post(.init(
            identifier: "typing-abandoned-\(event.id)", chatID: event.chatID, messageID: 0,
            title: event.name, subtitle: event.isGroup ? event.chatTitle : "",
            body: "was typing for \(Self.durationText(event.duration)) but sent nothing", isSilent: true))
    }

    func noteMessageForTyping(_ message: Message) {
        guard !message.isOutgoing, let sender = message.senderID else { return }
        let key = "\(message.chatID.rawValue)-\(sender.rawValue)"
        let cutoff = Date().addingTimeInterval(-600)
        var changed = false
        for index in typingLog.indices {
            let event = typingLog[index]
            guard event.startedAt > cutoff else { break }
            guard event.chatID == message.chatID.rawValue, event.userID == sender.rawValue,
                  event.outcome == .pending else { continue }
            typingLog[index].outcome = .sent
            typingLog[index].endedAt = typingLog[index].endedAt ?? Date()
            typingLog[index].messagePreview = message.text.isEmpty ? message.attachmentLabel : String(message.text.prefix(120))
            changed = true
        }
        openTypingSessions.removeValue(forKey: key)
        if changed { saveTypingLogSoon() }
    }

    /// Closes sessions whose "typing" stopped being renewed without a cancel.
    private func startTypingSweep() {
        guard typingSweepTask == nil else { return }
        typingSweepTask = Task { [weak self] in
            while let self, !self.openTypingSessions.isEmpty {
                try? await Task.sleep(for: .seconds(2))
                let now = Date()
                for (key, id) in self.openTypingSessions {
                    guard let event = self.typingLog.first(where: { $0.id == id }) else {
                        self.openTypingSessions.removeValue(forKey: key); continue
                    }
                    if now.timeIntervalSince(event.lastSeenAt) > Self.typingTimeout {
                        self.closeTyping(key: key, at: event.lastSeenAt)
                    }
                }
            }
            self?.typingSweepTask = nil
        }
    }

    private func saveTypingLogSoon() {
        let snapshot = typingLog
        Task.detached(priority: .utility) { TypingEvent.saveAll(snapshot) }
    }

    public func markTypingSeen() { unseenTypingCount = 0 }

    public func clearTypingLog() {
        typingLog = []
        openTypingSessions = [:]
        unseenTypingCount = 0
        TypingEvent.saveAll([])
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return s < 60 ? "\(max(s, 1)) s" : "\(s / 60) min \(s % 60) s"
    }

    // MARK: - Keyword alerts

    /// Notifies about messages containing one of the user's keywords, even
    /// in muted chats and channels — where Telegram itself stays silent.
    func checkKeywords(_ message: Message) {
        guard !message.isOutgoing, !message.isService, !message.text.isEmpty,
              let raw = UserDefaults.standard.string(forKey: TrackerSettings.keywordsKey) else { return }
        let keywords = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !keywords.isEmpty else { return }
        let text = message.text.lowercased()
        guard let hit = keywords.first(where: { text.contains($0) }) else { return }
        let chat = chatsByID[message.chatID]
        // Unmuted chats already notify through Telegram.
        guard chat?.isMuted == true || chat == nil else { return }
        if NSApp.isActive, selectedChatID == message.chatID { return }
        SystemNotifications.shared.post(.init(
            identifier: "keyword-\(message.chatID.rawValue)-\(message.id.rawValue)", chatID: message.chatID.rawValue,
            messageID: message.id.rawValue, title: "🔔 “\(hit)” in \(chat?.title ?? "a chat")",
            subtitle: message.senderName, body: String(message.text.prefix(200)), isSilent: false))
    }

    // MARK: - Deleted messages

    /// Counts and, if wanted, notifies about messages others just deleted.
    func announceDeleted(_ messages: [Message], in chatID: ChatID) {
        guard !messages.isEmpty else { return }
        if selectedDestination != .localArchive { unseenDeletedCount += messages.count }
        guard TrackerSettings.flag(TrackerSettings.deletedNotifyKey),
              chatsByID[chatID]?.isMuted != true else { return }
        let title = chatsByID[chatID]?.title ?? "Chat"
        let first = messages[0]
        let who = first.senderName.isEmpty ? title : first.senderName
        let text = first.text.isEmpty ? (first.attachmentLabel ?? "a message") : "“\(first.text.prefix(140))”"
        SystemNotifications.shared.post(.init(
            identifier: "deleted-\(chatID.rawValue)-\(first.id.rawValue)", chatID: chatID.rawValue,
            messageID: first.id.rawValue, title: "🗑 \(who) deleted \(messages.count == 1 ? "a message" : "\(messages.count) messages")",
            subtitle: who == title ? "" : title, body: text, isSilent: true))
    }

    public func markDeletedSeen() { unseenDeletedCount = 0 }

    public func editHistory(of message: Message) async -> [MessageArchive.Version] {
        guard keepsDeletedMessages, let archive else { return [] }
        return await archive.editHistory(chatID: message.chatID, messageID: message.id)
    }

    // MARK: - Story viewers

    /// While Nodogram runs, checks the user's live stories every minute and
    /// keeps every viewer it has not seen before.
    func startStoryViewerPolling() {
        storyPollTask?.cancel()
        storyPollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                await self?.refreshStoryViewers()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    public var myStoryIDs: [Int] {
        guard let me = myUserID else { return [] }
        return storyOwners[ChatID(me.rawValue)]?.storyIDs ?? []
    }

    public func refreshStoryViewers() async {
        guard let gateway else { return }
        var known = Set(storyViewers.map(\.id))
        var fresh: [StoryViewer] = []
        var reactionsChanged = false
        for storyID in myStoryIDs {
            for viewer in await gateway.storyViewers(storyID) {
                if !known.contains(viewer.id) {
                    known.insert(viewer.id)
                    fresh.append(viewer)
                } else if viewer.reaction != nil,
                          let index = storyViewers.firstIndex(where: { $0.id == viewer.id }),
                          storyViewers[index].reaction == nil {
                    // Reactions can arrive after the view.
                    storyViewers[index].reaction = viewer.reaction
                    reactionsChanged = true
                }
            }
        }
        if reactionsChanged, fresh.isEmpty { StoryViewersStore.save(storyViewers) }
        guard !fresh.isEmpty else { return }
        storyViewers = (fresh + storyViewers).sorted { $0.viewedAt > $1.viewedAt }
        StoryViewersStore.save(storyViewers)
        guard TrackerSettings.flag(TrackerSettings.storyViewsNotifyKey), let me = myUserID else { return }
        let names = fresh.prefix(3).map(\.name).joined(separator: ", ")
        SystemNotifications.shared.post(.init(
            identifier: "story-views-\(Date().timeIntervalSince1970)", chatID: me.rawValue, messageID: 0,
            title: "Story views",
            subtitle: "",
            body: fresh.count > 3 ? "\(names) and \(fresh.count - 3) more viewed your story" : "\(names) viewed your story",
            isSilent: true))
    }

    public func clearStoryViewers() {
        storyViewers = []
        StoryViewersStore.save([])
    }
}
