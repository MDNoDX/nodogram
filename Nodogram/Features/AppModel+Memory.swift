//  Archiving to the log channel: story views, typing that led nowhere, and
//  contact changes. These come from TDLib (the bot never sees them), so the
//  app posts them to the same private channel the Vault bot uses, keeping one
//  "memories" archive. Each line is also a local notification.

import Foundation
import OSLog
import NodogramDomain
import NodogramPlatform

extension AppModel {

    var logChannelID: ChatID? {
        VaultClient.fromEnvironment()?.logChannel.map(ChatID.init)
    }

    /// Posts one memory line to the channel (deduplicated for a few minutes).
    func archiveToChannel(_ text: String, dedupe: String? = nil) {
        guard let channel = logChannelID, let gateway else { return }
        if let dedupe {
            let now = Date()
            if let last = archivedRecently[dedupe], now.timeIntervalSince(last) < 300 { return }
            archivedRecently[dedupe] = now
        }
        Task { [weak self] in
            await gateway.ensureChat(channel)
            _ = self
            do { try await gateway.sendText(text, to: channel, silent: true) }
            catch { Logger(subsystem: "app.nodogram", category: "memory").error("channel archive failed: \(String(describing: error), privacy: .public)") }
        }
    }

    // MARK: - Contact changes

    func handleContactChange(_ user: UserID, name: String, nowMutual: Bool, wasMutual: Bool, isContact: Bool) {
        // They added you back (you already had them): now a mutual contact.
        if nowMutual && !wasMutual {
            notifyMemory("➕ \(name) added you to their contacts", "You are now mutual contacts.", user: user)
            archiveToChannel("➕ <b>\(Self.htmlEscape(name))</b> added you to their contacts — now mutual · \(Self.stamp())")
        } else if wasMutual && !nowMutual && isContact {
            // You still have them, but they are no longer mutual: they removed you.
            notifyMemory("➖ \(name) removed you from their contacts", "You still have them saved.", user: user)
            archiveToChannel("➖ <b>\(Self.htmlEscape(name))</b> removed you from their contacts · \(Self.stamp())")
        }
    }

    private func notifyMemory(_ title: String, _ body: String, user: UserID) {
        SystemNotifications.shared.post(.init(
            identifier: "contact-\(user.rawValue)-\(Int(Date().timeIntervalSince1970))",
            chatID: user.rawValue, messageID: 0, title: title, subtitle: "", body: body, isSilent: false))
    }

    static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func stamp() -> String {
        Date().formatted(date: .abbreviated, time: .shortened)
    }
}
