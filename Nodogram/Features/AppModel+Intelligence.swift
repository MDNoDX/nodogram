//  Reading help: translate a whole chat, and summarise what you missed with
//  Apple's on-device model (macOS 26 with Apple Intelligence). The summary
//  never leaves this Mac and nothing is used for training (API terms 1.5).

import Foundation
import NodogramDomain
#if canImport(FoundationModels)
import FoundationModels
#endif

extension AppModel {

    // MARK: - Chat translation

    public func isTranslating(_ chat: ChatID) -> Bool { translatedChats.contains(chat) }

    public func setTranslating(_ chat: ChatID, _ on: Bool) {
        if on { translatedChats.insert(chat) } else { translatedChats.remove(chat) }
    }

    /// The translation of a message, fetched once and cached.
    public func translation(for message: Message) -> String? { translations[message.uniqueKey] }

    public func ensureTranslation(for message: Message) {
        let key = message.uniqueKey
        guard isTranslating(message.chatID), !message.isOutgoing, !message.text.isEmpty,
              translations[key] == nil, pendingTranslations.insert(key).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            let text = await self.translate(message) ?? ""
            self.pendingTranslations.remove(key)
            // Skip when it came back the same (already in the target language).
            self.translations[key] = text.trimmingCharacters(in: .whitespacesAndNewlines) == message.text
                .trimmingCharacters(in: .whitespacesAndNewlines) ? "" : text
        }
    }

    // MARK: - Summary

    public var canSummarize: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Summarises the latest messages of the open chat.
    public func summarizeChat() async -> String {
        let recent = messages.filter { !$0.isService && !$0.text.isEmpty }.suffix(80)
        guard !recent.isEmpty else { return "There is nothing to summarise yet." }
        let transcript = recent.map { m in
            "\(m.isOutgoing ? "Me" : (m.senderName.isEmpty ? (selectedChat?.title ?? "Them") : m.senderName)): \(m.text.prefix(500))"
        }.joined(separator: "\n")
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                return "Apple Intelligence isn't available on this Mac. Turn it on in System Settings → Apple Intelligence & Siri."
            }
            let session = LanguageModelSession(instructions: """
                You summarise chat conversations for the reader. Be brief: 3 to 6 bullet points with the key \
                facts, decisions, questions waiting for the reader, and dates or numbers. Use the conversation's \
                own language. Do not invent anything.
                """)
            do {
                return try await session.respond(to: "Summarise this conversation:\n\n\(transcript)").content
            } catch {
                return "Couldn't summarise: \(error.localizedDescription)"
            }
        }
        #endif
        return "Summaries need macOS 26 with Apple Intelligence."
    }
}
