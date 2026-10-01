//  Renders read state honestly.
//
//  This is the UI half of the differentiator described in
//  Documentation/ARCHITECTURE.md §6.2. Every one of Telegram's five outcomes
//  gets its own truthful copy. Crucially, there is no branch that invents a
//  timestamp: the domain type only carries a Date in the `.read` case, so
//  "Read at …" is unwritable unless the server actually told us.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ReadReceiptLabel: View {
    private let readDate: MessageReadDate?
    private let sendState: MessageSendState?
    private let showsPreciseSeconds: Bool

    public init(
        readDate: MessageReadDate?,
        sendState: MessageSendState?,
        showsPreciseSeconds: Bool = false
    ) {
        self.readDate = readDate
        self.sendState = sendState
        self.showsPreciseSeconds = showsPreciseSeconds
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(Theme.Typography.timestamp)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .help(tooltip)
    }

    private var label: String {
        // Local send state takes precedence: until the server has it, there is
        // no server-side read state to report.
        if let sendState {
            switch sendState {
            case .sending: return L10n.sending
            case .failed: return L10n.failedToSend
            case .offlinePending: return L10n.queuedOffline
            case .sent: break
            }
        }

        guard let readDate else { return L10n.delivered }

        switch readDate {
        case .read(let date):
            let time = showsPreciseSeconds
                ? date.formatted(.dateTime.hour().minute().second())
                : date.formatted(.dateTime.hour().minute())
            return "\(L10n.readAt) \(time)"
        case .unread:
            return L10n.delivered
        case .tooOld:
            return L10n.readTimeUnavailable
        case .recipientPrivacyRestricted:
            return L10n.readTimeHiddenByRecipient
        case .ownPrivacyRestricted:
            return L10n.readTimeHiddenByYou
        }
    }

    private var icon: String {
        if let sendState {
            switch sendState {
            case .sending: return "clock"
            case .failed: return "exclamationmark.triangle"
            case .offlinePending: return "wifi.slash"
            case .sent: break
            }
        }
        guard let readDate else { return "checkmark" }
        return readDate.isRead ? "checkmark.circle.fill" : "checkmark"
    }

    private var tint: Color {
        if let sendState, case .failed = sendState { return Theme.failure }
        if let sendState, case .offlinePending = sendState { return Theme.warning }
        guard let readDate, readDate.isRead else { return Theme.tertiaryText }
        return readDate.isPrivacyWithheld ? Theme.tertiaryText : Theme.accent
    }

    /// Explains the privacy cases on hover rather than leaving the user to
    /// wonder why a time is missing.
    private var tooltip: String {
        guard let readDate else { return "" }
        switch readDate {
        case .read(let date):
            return RelativeTimeFormatter.exact(date)
        case .tooOld:
            return "Telegram no longer stores when this was read."
        case .recipientPrivacyRestricted:
            return "This person has read receipts turned off."
        case .ownPrivacyRestricted:
            return "Telegram only shows you others' read times if you share yours."
        case .unread:
            return ""
        }
    }
}
