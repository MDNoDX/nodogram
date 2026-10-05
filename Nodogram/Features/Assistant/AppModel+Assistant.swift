//  The AI assistant: understand a person from your chat, suggest replies in
//  your own style, and look over a message before you send it.
//
//  What is sent: message text only, as "Me" and "Them" (group members as
//  "Person A", "Person B"…), with times. No names, phone numbers, usernames
//  or media. Secret and copy-protected chats are never sent.

import Foundation
import NodogramDomain
import NodogramTelegram

public struct AssistantAnalysis: Codable, Sendable {
    public var summary: String
    public var relationship: String
    public var theirAttitude: String
    public var warmth: Int
    public var interest: Int
    public var theirStyle: String
    public var topics: [String]
    public var openLoops: [String]
    public var advice: [String]
    public var analyzedAt: Date
    public var messageCount: Int
    // Added for depth; optional so older saved analyses still decode.
    public var personality: String?
    public var communicationPattern: String?
    public var interestTrend: String?
    public var greenFlags: [String]?
    public var watchOuts: [String]?
    /// Durable facts the assistant remembers about this person, carried into
    /// every later analysis and reply — the "memory," kept on this Mac.
    public var memory: [String]?
}

/// Facts computed on this Mac, without any AI.
public struct ChatStats: Sendable {
    public var mine = 0
    public var theirs = 0
    public var myMedianReply: TimeInterval?
    public var theirMedianReply: TimeInterval?
    public var iStarted = 0
    public var theyStarted = 0
    public var theirActiveHour: Int?
    public var deletedByThem = 0
    public var since: Date?
}

public struct ReplySuggestion: Codable, Sendable, Hashable {
    public let text: String
    public let tone: String
}

public struct DraftReview: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case checking
        case result(verdict: String, reason: String, improved: String)
        case failed(String)
    }
    public let chatID: ChatID
    public let text: String
    public var state: State
}

extension AppModel {

    // MARK: - Availability

    public var assistantReady: Bool {
        AssistantSettings.provider == "apple" ? canSummarize : AssistantSettings.geminiKey != nil
    }

    func assistantAllowed(in chat: Chat?) -> String? {
        guard let chat else { return "Open a chat first." }
        if chat.hasProtectedContent { return "The assistant is off in chats that restrict saving content." }
        if case .secret = chat.kind { return "The assistant is off in secret chats." }
        if AssistantSettings.provider == "gemini", !UserDefaults.standard.bool(forKey: AssistantSettings.consentKey) {
            return "Allow sending chat text to Gemini first: Settings → AI Assistant."
        }
        return nil
    }

    // MARK: - Transcript

    /// The latest messages of a chat, loading older pages up to `depth`.
    func assistantMessages(in chatID: ChatID, depth: Int) async -> [Message] {
        var all = chatID == selectedChatID ? messages : []
        guard let gateway else { return all }
        while all.count < depth {
            let before = all.map(\.id).min { $0.rawValue < $1.rawValue }
            guard let page = try? await gateway.history(chatID, before: before, limit: 100), !page.isEmpty else { break }
            let known = Set(all.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            if fresh.isEmpty { break }
            all += fresh
        }
        return Array(all.filter { !$0.isService }.sorted { $0.id.rawValue < $1.id.rawValue }.suffix(depth))
    }

    /// "Me" / "Them" (or "Person A"…) lines with day and time.
    static func transcript(_ messages: [Message], isGroup: Bool) -> String {
        var letters: [Int64: String] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM HH:mm"
        return messages.map { m in
            let who: String
            if m.isOutgoing { who = "Me" }
            else if isGroup {
                let key = m.senderID?.rawValue ?? 0
                if letters[key] == nil { letters[key] = "Person \(String(UnicodeScalar(65 + letters.count % 26)!))" }
                who = letters[key]!
            } else { who = "Them" }
            var body = m.text.isEmpty ? "" : String(m.text.prefix(600))
            if let label = m.attachmentLabel { body = "[\(label)] " + body }
            if m.isDeleted { body += " (they deleted this)" }
            return "[\(formatter.string(from: m.date))] \(who): \(body)"
        }.joined(separator: "\n")
    }

    static func stats(_ messages: [Message]) -> ChatStats {
        var stats = ChatStats()
        stats.since = messages.first?.date
        var myReplies: [TimeInterval] = [], theirReplies: [TimeInterval] = []
        var hours: [Int: Int] = [:]
        var previous: Message?
        for m in messages {
            if m.isOutgoing { stats.mine += 1 } else {
                stats.theirs += 1
                hours[Calendar.current.component(.hour, from: m.date), default: 0] += 1
                if m.isDeleted { stats.deletedByThem += 1 }
            }
            if let p = previous {
                let gap = m.date.timeIntervalSince(p.date)
                if gap > 6 * 3600 { if m.isOutgoing { stats.iStarted += 1 } else { stats.theyStarted += 1 } }
                else if p.isOutgoing != m.isOutgoing, gap < 24 * 3600 {
                    if m.isOutgoing { myReplies.append(gap) } else { theirReplies.append(gap) }
                }
            }
            previous = m
        }
        func median(_ values: [TimeInterval]) -> TimeInterval? {
            guard !values.isEmpty else { return nil }
            return values.sorted()[values.count / 2]
        }
        stats.myMedianReply = median(myReplies)
        stats.theirMedianReply = median(theirReplies)
        stats.theirActiveHour = hours.max { $0.value < $1.value }?.key
        return stats
    }

    private var answerLanguage: String {
        UserDefaults.standard.string(forKey: "ai.answerLanguage") ?? "Uzbek (Latin script)"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let cleaned = AppleProvider.stripFences(text)
        guard let data = cleaned.data(using: .utf8) else { throw AIError.empty }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Analysis

    public func analyzeChat(_ chatID: ChatID) async throws -> (AssistantAnalysis, ChatStats) {
        let chat = chatsByID[chatID]
        if let reason = assistantAllowed(in: chat) { throw AIError.unavailable(reason) }
        let provider = try AssistantSettings.currentProvider()
        let history = await assistantMessages(in: chatID, depth: AssistantSettings.depth)
        guard history.count >= 4 else { throw AIError.unavailable("There isn't enough conversation yet to analyse.") }
        let isGroup = chatID.rawValue < 0
        let stats = Self.stats(history)
        let strOf: (String) -> [String: String] = { _ in ["type": "STRING"] }
        _ = strOf
        let arr: [String: Any] = ["type": "ARRAY", "items": ["type": "STRING"]]
        let schema: [String: Any] = ["type": "OBJECT", "properties": [
            "summary": ["type": "STRING"], "relationship": ["type": "STRING"], "theirAttitude": ["type": "STRING"],
            "personality": ["type": "STRING"], "communicationPattern": ["type": "STRING"], "interestTrend": ["type": "STRING"],
            "warmth": ["type": "INTEGER"], "interest": ["type": "INTEGER"], "theirStyle": ["type": "STRING"],
            "topics": arr, "openLoops": arr, "advice": arr, "greenFlags": arr, "watchOuts": arr, "memory": arr,
        ], "required": ["summary", "relationship", "theirAttitude", "personality", "communicationPattern", "interestTrend",
                        "warmth", "interest", "theirStyle", "topics", "openLoops", "advice", "greenFlags", "watchOuts", "memory"]]
        let priorMemory = (assistantAnalyses[chatID.rawValue]?.memory ?? []).joined(separator: "; ")
        let system = """
            You are a sharp, warm relationship and communication coach helping the user ("Me") truly understand \
            another person from their real chat, and respond well — authentically, never manipulatively. \
            Think like a thoughtful psychologist: read tone, effort, timing, initiative, emotional cues and how \
            they change over time. Be honest and specific; ground every claim in the messages; flag guesses as \
            guesses; say when evidence is thin. Never invent facts and never encourage deceiving or pressuring anyone.
            Fields: warmth (0-100) how warm/positive they are toward Me; interest (0-100) how engaged they are \
            (reply speed, effort, questions, who initiates); personality: their apparent character and what they \
            value; communicationPattern: how they communicate (initiative, reply rhythm, emoji, directness); \
            interestTrend: is their interest rising, steady or cooling, with evidence; greenFlags: positive signs; \
            watchOuts: honest cautions or mixed signals; openLoops: questions/promises still waiting; advice: 3-5 \
            concrete, kind, practical tips for Me; memory: 4-10 short durable facts worth remembering about this \
            person (preferences, important events, boundaries, inside references) — merge and refine the earlier \
            memory, keep what still matters, drop the stale. Write every field in \(answerLanguage).
            """
        let prompt = """
            \(isGroup ? "This is a group chat; analyse the group's attitude toward Me." : "This is a private chat between Me and Them.")
            \(priorMemory.isEmpty ? "" : "What you remembered before about this person: \(priorMemory)")
            Local facts: Me sent \(stats.mine), Them sent \(stats.theirs) messages; Me started \(stats.iStarted) \
            conversations, Them \(stats.theyStarted); median reply — Me \(Self.minutes(stats.myMedianReply)), \
            Them \(Self.minutes(stats.theirMedianReply)); their most active hour: \(stats.theirActiveHour.map { "\($0):00" } ?? "unknown").

            Conversation (oldest first):
            \(Self.transcript(history, isGroup: isGroup))
            """
        struct Raw: Decodable {
            let summary, relationship, theirAttitude, personality, communicationPattern, interestTrend, theirStyle: String
            let warmth, interest: Int
            let topics, openLoops, advice, greenFlags, watchOuts, memory: [String]
        }
        let raw = try Self.decode(Raw.self, from: try await provider.generate(AIRequest(system: system, prompt: prompt, schema: schema)))
        let analysis = AssistantAnalysis(
            summary: raw.summary, relationship: raw.relationship, theirAttitude: raw.theirAttitude,
            warmth: min(max(raw.warmth, 0), 100), interest: min(max(raw.interest, 0), 100), theirStyle: raw.theirStyle,
            topics: raw.topics, openLoops: raw.openLoops, advice: raw.advice, analyzedAt: Date(), messageCount: history.count,
            personality: raw.personality, communicationPattern: raw.communicationPattern, interestTrend: raw.interestTrend,
            greenFlags: raw.greenFlags, watchOuts: raw.watchOuts, memory: raw.memory)
        assistantAnalyses[chatID.rawValue] = analysis
        AssistantStore.save(assistantAnalyses)
        return (analysis, stats)
    }

    public func localStats(_ chatID: ChatID) async -> ChatStats {
        Self.stats(await assistantMessages(in: chatID, depth: AssistantSettings.depth))
    }

    static func minutes(_ value: TimeInterval?) -> String {
        guard let value else { return "unknown" }
        if value < 60 { return "under a minute" }
        if value < 3600 { return "\(Int(value / 60)) min" }
        return String(format: "%.1f h", value / 3600)
    }

    // MARK: - Suggestions

    public func suggestReplies() async throws -> [ReplySuggestion] {
        guard let chatID = selectedChatID else { return [] }
        if let reason = assistantAllowed(in: selectedChat) { throw AIError.unavailable(reason) }
        let provider = try AssistantSettings.currentProvider()
        let history = await assistantMessages(in: chatID, depth: 60)
        let schema: [String: Any] = ["type": "OBJECT", "properties": [
            "replies": ["type": "ARRAY", "items": ["type": "OBJECT", "properties": [
                "text": ["type": "STRING"], "tone": ["type": "STRING"]], "required": ["text", "tone"]]],
        ], "required": ["replies"]]
        let memory = (assistantAnalyses[chatID.rawValue]?.memory ?? []).joined(separator: "; ")
        let system = """
            You are Me's reply coach. Suggest what Me could send next in this chat. Write exactly like Me writes \
            here — same language, script, length, emoji habits and formality — so it sounds like Me, not a bot. \
            Read the other person's mood and what they just said, and make each reply land well and move things \
            forward naturally and honestly (never manipulative or fake). Give 3 genuinely different options \
            (e.g. short and easy, warm and personal, and one that opens the next step). The tone label is 1-2 \
            words in \(answerLanguage).
            """
        let prompt = """
            \(memory.isEmpty ? "" : "What you remember about this person: \(memory)\n")\
            Conversation (latest last):
            \(Self.transcript(history, isGroup: chatID.rawValue < 0))

            Me's draft so far: \(draftText.isEmpty ? "(empty)" : draftText)
            """
        struct Raw: Decodable { let replies: [ReplySuggestion] }
        return try Self.decode(Raw.self, from: try await provider.generate(AIRequest(system: system, prompt: prompt, schema: schema, fast: true))).replies
    }

    /// Writes a full reply for a goal the user states ("set up a meeting",
    /// "apologise warmly", "say no politely"), in Me's own voice.
    public func composeReply(goal: String) async throws -> String {
        guard let chatID = selectedChatID else { return "" }
        if let reason = assistantAllowed(in: selectedChat) { throw AIError.unavailable(reason) }
        let provider = try AssistantSettings.currentProvider()
        let history = await assistantMessages(in: chatID, depth: 120)
        let memory = (assistantAnalyses[chatID.rawValue]?.memory ?? []).joined(separator: "; ")
        let system = """
            You write one message for Me to send, in Me's exact style and language as seen in this chat. \
            Honour Me's goal while fitting the conversation and the other person's mood. Be authentic, warm \
            and natural — never robotic, manipulative or over-long. Reply with the message text only, no quotes, \
            no explanation.
            """
        let prompt = """
            \(memory.isEmpty ? "" : "What you remember about this person: \(memory)\n")\
            Conversation (latest last):
            \(Self.transcript(history, isGroup: chatID.rawValue < 0))

            Me's goal for the reply: \(goal)
            """
        return AppleProvider.stripFences(try await provider.generate(AIRequest(system: system, prompt: prompt)))
    }

    // MARK: - Review before sending

    /// The composer's send: straight through, or past the assistant first.
    public func sendFromComposer() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AssistantSettings.reviewsBeforeSending, assistantReady, let chatID = selectedChatID,
              assistantAllowed(in: selectedChat) == nil, text.count >= 2, case .normal = composerMode else {
            submitComposer()
            return
        }
        draftReview = DraftReview(chatID: chatID, text: text, state: .checking)
        Task { [weak self] in
            guard let self else { return }
            do {
                let (verdict, reason, improved) = try await self.reviewDraft(text, in: chatID)
                guard self.draftReview?.text == text else { return }
                if verdict == "send" {
                    self.draftReview = nil
                    self.submitComposer()
                } else {
                    self.draftReview?.state = .result(verdict: verdict, reason: reason, improved: improved)
                }
            } catch {
                guard self.draftReview?.text == text else { return }
                self.draftReview?.state = .failed(error.localizedDescription)
            }
        }
    }

    public func sendDespiteReview() {
        draftReview = nil
        submitComposer()
    }

    public func useImprovedDraft() {
        if case .result(_, _, let improved)? = draftReview?.state, !improved.isEmpty { draftText = improved }
        draftReview = nil
    }

    public func dismissReview() { draftReview = nil }

    func reviewDraft(_ text: String, in chatID: ChatID) async throws -> (String, String, String) {
        let provider = try AssistantSettings.currentProvider()
        let history = await assistantMessages(in: chatID, depth: 40)
        let schema: [String: Any] = ["type": "OBJECT", "properties": [
            "verdict": ["type": "STRING", "enum": ["send", "revise", "hold"]],
            "reason": ["type": "STRING"], "improved": ["type": "STRING"],
        ], "required": ["verdict", "reason", "improved"]]
        let system = """
            You look over a message Me is about to send, in the context of the chat. verdict "send" when it is fine \
            (most messages are — don't nitpick); "revise" when the tone, clarity or facts could cause a \
            misunderstanding or hurt; "hold" when sending now is likely a mistake (anger, oversharing, wrong \
            person, sensitive data). reason: one short sentence in \(answerLanguage). improved: a better version \
            in the message's own language and Me's style, or "" when verdict is send.
            """
        let prompt = "Chat (latest last):\n\(Self.transcript(history, isGroup: chatID.rawValue < 0))\n\nMessage Me is about to send:\n\(text)"
        struct Raw: Decodable { let verdict, reason, improved: String }
        let raw = try Self.decode(Raw.self, from: try await provider.generate(AIRequest(system: system, prompt: prompt, schema: schema, fast: true)))
        return (raw.verdict, raw.reason, raw.improved)
    }

    // MARK: - Ask

    public func askAboutChat(_ question: String) async throws -> String {
        guard let chatID = selectedChatID else { return "" }
        if let reason = assistantAllowed(in: selectedChat) { throw AIError.unavailable(reason) }
        let provider = try AssistantSettings.currentProvider()
        let history = await assistantMessages(in: chatID, depth: AssistantSettings.depth)
        let system = "Answer Me's question about this chat, using only what the messages show. Be concise. Answer in \(answerLanguage)."
        return try await provider.generate(AIRequest(
            system: system, prompt: "Chat:\n\(Self.transcript(history, isGroup: chatID.rawValue < 0))\n\nQuestion: \(question)"))
    }
}

/// Analyses kept on this Mac, so reopening a chat shows the last one.
enum AssistantStore {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nodogram/assistant-analyses.json")

    static func load() -> [Int64: AssistantAnalysis] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([Int64: AssistantAnalysis].self, from: data)) ?? [:]
    }

    static func save(_ value: [Int64: AssistantAnalysis]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
