//  Renders read state honestly.
//
//  The UI half of the read-time differentiator (ARCHITECTURE.md §6.2). Three
//  levels of knowledge are kept apart, because merging them is how a client
//  ends up implying more than it knows:
//
//    - not yet read
//    - read, time not (yet) known — from Telegram's read-outbox marker
//    - read at an exact, server-confirmed time — from getMessageReadDate
//
//  There is no branch that invents a time: only `.read(Date)` carries one.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ReadReceiptLabel: View {
    public enum Style {
        /// Checkmarks only, inside a bubble.
        case compact
        /// Checkmarks plus words, under the latest outgoing message.
        case detailed
    }

    private let message: Message
    private let style: Style

    public init(message: Message, style: Style) {
        self.message = message
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: style == .compact ? 9 : 10, weight: .semibold))
            if style == .detailed {
                Text(label)
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(tint)
        .help(tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var isRead: Bool {
        message.isReadByRecipient || (message.readDate?.isRead ?? false)
    }

    private var label: String {
        switch message.sendState {
        case .sending: return L10n.sending
        case .offlinePending: return L10n.queuedOffline
        case .failed: return L10n.failedToSend
        case .sent, nil: break
        }

        switch message.readDate {
        case .read(let date):
            return "Read \(RelativeTimeFormatter.readTime(date))"
        case .tooOld:
            return L10n.readTimeUnavailable
        case .recipientPrivacyRestricted:
            return L10n.readTimeHiddenByRecipient
        case .ownPrivacyRestricted:
            return L10n.readTimeHiddenByYou
        case .unread, nil:
            return isRead ? "Read" : L10n.delivered
        }
    }

    private var icon: String {
        switch message.sendState {
        case .sending, .offlinePending: return "clock"
        case .failed: return "exclamationmark.circle.fill"
        case .sent, nil: return isRead ? "checkmark.circle.fill" : "checkmark"
        }
    }

    private var tint: AnyShapeStyle {
        switch message.sendState {
        case .failed: return AnyShapeStyle(Theme.failure)
        case .offlinePending: return AnyShapeStyle(Theme.warning)
        case .sending: return AnyShapeStyle(.tertiary)
        case .sent, nil:
            // Privacy-withheld states stay muted: colouring them like a
            // confirmed read time would overstate what is known.
            if let readDate = message.readDate, readDate.isPrivacyWithheld { return AnyShapeStyle(.secondary) }
            return isRead ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary)
        }
    }

    private var tooltip: String {
        if case .failed(let reason) = message.sendState { return reason }
        switch message.readDate {
        case .read(let date): return "Read \(RelativeTimeFormatter.exact(date))"
        case .tooOld: return "Telegram no longer stores when this was read."
        case .recipientPrivacyRestricted: return "This person has read receipts turned off."
        case .ownPrivacyRestricted: return "Telegram shows others' read times only if you share yours."
        case .unread, nil:
            return isRead ? "Read. The exact time is shown for recent messages in private chats." : ""
        }
    }
}
