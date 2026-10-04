//  Turning TDLib's notification decisions into macOS notifications, and
//  handling Reply / Mark as Read / tap.

import AppKit
import Foundation
import NodogramDomain
import NodogramPlatform

extension AppModel {

    public static let notificationsEnabledKey = "notifications.enabled"
    public static let dockBadgeKey = "notifications.dockBadge"

    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    func deliverNotifications(_ notifications: [ChatNotification]) {
        guard Self.flag(Self.notificationsEnabledKey) else { return }
        for notification in notifications {
            let chat = chatsByID[notification.chatID]
            // Looking at that chat right now: a banner would only interrupt.
            if NSApp.isActive, notification.chatID == selectedChatID { continue }
            if notification.message.isOutgoing { continue }

            let isGroup: Bool = {
                switch chat?.kind {
                case .basicGroup, .supergroup: return true
                default: return false
                }
            }()
            let message = notification.message
            let body = message.text.isEmpty ? (message.attachmentLabel ?? "Message") :
                (message.attachmentLabel.map { "\($0) · \(message.text)" } ?? message.text)

            SystemNotifications.shared.post(.init(
                identifier: "n-\(notification.groupID)-\(notification.id)",
                chatID: notification.chatID.rawValue,
                messageID: message.id.rawValue,
                title: chat?.title ?? "New message",
                subtitle: isGroup ? message.senderName : "",
                body: body,
                isSilent: notification.isSilent))
        }
    }

    /// Wires notification actions back into the app. Called once at startup.
    func connectNotifications() {
        SystemNotifications.shared.onResponse = { [weak self] response in
            guard let self else { return }
            switch response {
            case .open(let chatID, let messageID):
                self.selectedDestination = .allChats
                self.jump(to: MessageID(messageID), in: ChatID(chatID))
            case .reply(let chatID, let text):
                guard let gateway = self.gateway else { return }
                Task { try? await gateway.sendText(text, to: ChatID(chatID)) }
                self.markAsRead(ChatID(chatID))
            case .markRead(let chatID):
                self.markAsRead(ChatID(chatID))
                SystemNotifications.shared.removeAll(forChat: chatID)
            }
        }
    }

    /// The Dock badge mirrors the unread total, muted chats excluded.
    func refreshBadge() {
        SystemNotifications.shared.setBadge(Self.flag(Self.dockBadgeKey) ? unreadTotal : 0)
    }
}
