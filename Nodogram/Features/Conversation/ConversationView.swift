//  Conversation pane.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ConversationView: View {
    private let chat: Chat?
    private let messages: [Message]
    @Binding private var draftText: String
    private let draftIndicatorVisible: Bool
    private let onSend: () -> Void

    public init(
        chat: Chat?,
        messages: [Message],
        draftText: Binding<String>,
        draftIndicatorVisible: Bool,
        onSend: @escaping () -> Void
    ) {
        self.chat = chat
        self.messages = messages
        self._draftText = draftText
        self.draftIndicatorVisible = draftIndicatorVisible
        self.onSend = onSend
    }

    public var body: some View {
        if let chat {
            VStack(spacing: 0) {
                MessageTimeline(messages: messages)
                Divider()
                ComposerView(
                    text: $draftText,
                    draftIndicatorVisible: draftIndicatorVisible,
                    onSend: onSend
                )
            }
            .navigationTitle(chat.title)
            .navigationSubtitle(subtitle(for: chat))
        } else {
            EmptyStateView(
                icon: "bubble.left.and.text.bubble.right",
                title: L10n.noConversationTitle,
                message: L10n.noConversationBody
            )
        }
    }

    private func subtitle(for chat: Chat) -> String {
        switch chat.kind {
        case .privateChat: return ""
        case .basicGroup, .supergroup: return "Group"
        case .channel: return "Channel"
        case .secret: return "Secret chat"
        }
    }
}

struct MessageTimeline: View {
    let messages: [Message]

    var body: some View {
        if messages.isEmpty {
            EmptyStateView(
                icon: "text.bubble",
                title: "No messages yet",
                message: "Messages in this conversation will appear here."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(groupedByDay, id: \.day) { section in
                            DateSeparator(date: section.day)
                            ForEach(section.messages) { message in
                                MessageRow(message: message).id(message.id)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private struct DaySection {
        let day: Date
        let messages: [Message]
    }

    /// Date separators, without repeating the date unnecessarily (brief §65).
    private var groupedByDay: [DaySection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: messages) {
            calendar.startOfDay(for: $0.date)
        }
        return groups.keys.sorted().map { day in
            DaySection(day: day, messages: groups[day]?.sorted { $0.date < $1.date } ?? [])
        }
    }
}

struct DateSeparator: View {
    let date: Date

    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day()).uppercased()
        }
        return date.formatted(.dateTime.year().month(.wide).day()).uppercased()
    }

    var body: some View {
        Text(label)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                if !message.isOutgoing && !message.senderName.isEmpty {
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                Text(message.text)
                    .font(Theme.Typography.messageBody)
                    .textSelection(.enabled)
                    .foregroundStyle(Theme.primaryText)

                HStack(spacing: 5) {
                    Text(message.date.formatted(.dateTime.hour().minute()))
                        .font(Theme.Typography.timestamp)
                        .foregroundStyle(Theme.tertiaryText)
                        .help(RelativeTimeFormatter.exact(message.date))

                    if message.wasEdited {
                        Text(L10n.edited)
                            .font(Theme.Typography.timestamp)
                            .foregroundStyle(Theme.tertiaryText)
                    }

                    if message.isOutgoing {
                        ReadReceiptLabel(
                            readDate: message.readDate,
                            sendState: message.sendState
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                message.isOutgoing ? Theme.accentSoft : Theme.listBackground,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius)
            )

            if !message.isOutgoing { Spacer(minLength: 60) }
        }
    }
}
