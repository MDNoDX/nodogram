//  macOS notifications.
//
//  TDLib decides *what* should notify (it already applies mute settings,
//  mention rules and exceptions); this shows it the macOS way: grouped per chat,
//  with Reply and Mark as Read actions, and a "privacy mode" that hides text.

import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
public final class SystemNotifications: NSObject {
    public static let shared = SystemNotifications()

    public struct Payload: Sendable {
        public let identifier: String
        public let chatID: Int64
        public let messageID: Int64
        public let title: String
        public let subtitle: String
        public let body: String
        public let isSilent: Bool

        public init(identifier: String, chatID: Int64, messageID: Int64, title: String,
                    subtitle: String, body: String, isSilent: Bool) {
            self.identifier = identifier; self.chatID = chatID; self.messageID = messageID
            self.title = title; self.subtitle = subtitle; self.body = body; self.isSilent = isSilent
        }
    }

    public enum Response: Sendable {
        case open(chatID: Int64, messageID: Int64)
        case reply(chatID: Int64, text: String)
        case markRead(chatID: Int64)
    }

    /// Hide message text in notifications ("You have a new message").
    public static let privacyModeKey = "notifications.privacyMode"

    public var onResponse: ((Response) -> Void)?
    private var requestedAuthorization = false

    private static let category = "nodogram.message"
    private static let replyAction = "nodogram.reply"
    private static let readAction = "nodogram.read"

    /// Registers the delegate and actions. Call at launch, before any
    /// notification can be tapped.
    public func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyAction, title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Message")
        let read = UNNotificationAction(identifier: Self.readAction, title: "Mark as Read", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [reply, read], intentIdentifiers: [])
        ])
    }

    /// Asks once, the first time there is something to show — not at launch,
    /// before the user knows why the app wants it.
    private func ensureAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined, !requestedAuthorization {
            requestedAuthorization = true
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    public func post(_ payload: Payload) {
        Task {
            guard await ensureAuthorization() else { return }
            let privacy = UserDefaults.standard.bool(forKey: Self.privacyModeKey)
            let content = UNMutableNotificationContent()
            content.title = privacy ? "Nodogram" : payload.title
            content.subtitle = privacy ? "" : payload.subtitle
            content.body = privacy ? "You have a new message" : payload.body
            content.threadIdentifier = "chat-\(payload.chatID)"   // groups per chat
            content.categoryIdentifier = Self.category
            content.sound = payload.isSilent ? nil : .default
            content.userInfo = ["chatID": payload.chatID, "messageID": payload.messageID]
            let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    public func remove(groupID: Int, ids: [Int]) {
        let identifiers = ids.map { "n-\(groupID)-\($0)" }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func removeAll(forChat chatID: Int64) {
        Task {
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            let matching = delivered.filter { $0.request.content.threadIdentifier == "chat-\(chatID)" }
                .map(\.request.identifier)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: matching)
        }
    }

    public func setBadge(_ count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? (count > 999 ? "999+" : "\(count)") : nil
    }
}

extension SystemNotifications: UNUserNotificationCenterDelegate {
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let chatID = (info["chatID"] as? Int64) ?? (info["chatID"] as? NSNumber)?.int64Value ?? 0
        let messageID = (info["messageID"] as? Int64) ?? (info["messageID"] as? NSNumber)?.int64Value ?? 0
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText ?? ""

        await MainActor.run {
            let handler = SystemNotifications.shared.onResponse
            switch action {
            case Self.replyAction where !text.isEmpty:
                handler?(.reply(chatID: chatID, text: text))
            case Self.readAction:
                handler?(.markRead(chatID: chatID))
            default:
                NSApp.activate()
                handler?(.open(chatID: chatID, messageID: messageID))
            }
        }
    }

    /// While Nodogram is in front, banners still show — unless the user is
    /// already looking at that chat (decided before posting).
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
