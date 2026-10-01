//  Conversation list.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ChatListView: View {
    private let chats: [Chat]
    private let destination: SidebarDestination
    @Binding private var selectedChatID: ChatID?
    @Binding private var searchText: String

    public init(
        chats: [Chat],
        destination: SidebarDestination,
        selectedChatID: Binding<ChatID?>,
        searchText: Binding<String>
    ) {
        self.chats = chats
        self.destination = destination
        self._selectedChatID = selectedChatID
        self._searchText = searchText
    }

    public var body: some View {
        Group {
            if chats.isEmpty {
                EmptyStateView(
                    icon: "bubble.left.and.bubble.right",
                    title: L10n.noChatsTitle,
                    message: L10n.noChatsBody
                )
            } else {
                List(chats, selection: $selectedChatID) { chat in
                    ChatRow(chat: chat).tag(chat.id)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(destination.title)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
    }
}

struct ChatRow: View {
    let chat: Chat

    private var timestamp: String {
        guard let date = chat.lastMessage?.date else { return "" }
        return RelativeTimeFormatter.short(date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Avatar(title: chat.title, seed: chat.id.rawValue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(chat.title)
                        .font(Theme.Typography.chatTitle)
                        .lineLimit(1)

                    if chat.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Verified")
                    }

                    Spacer(minLength: 4)

                    Text(timestamp)
                        .font(Theme.Typography.timestamp)
                        .foregroundStyle(Theme.tertiaryText)
                }

                HStack(spacing: 4) {
                    if chat.hasDraft {
                        // Text label, not just colour — the draft indicator has
                        // to survive colour-blindness and greyscale.
                        Text("Draft")
                            .font(Theme.Typography.timestamp)
                            .foregroundStyle(Theme.warning)
                    }

                    if chat.lastMessage?.hasAttachment == true {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityLabel("Has attachment")
                    }

                    Text(previewText)
                        .font(Theme.Typography.chatPreview)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if chat.isMuted {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                            .accessibilityLabel("Muted")
                    }

                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.tertiaryText)
                            .accessibilityLabel("Pinned")
                    }

                    if chat.unreadCount > 0 {
                        UnreadBadge(count: chat.unreadCount, isMuted: chat.isMuted)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Metrics.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var previewText: String {
        guard let last = chat.lastMessage else { return "" }
        if chat.showsSenderInPreview, let sender = last.senderName {
            return "\(sender): \(last.text)"
        }
        return last.text
    }

    /// A single spoken sentence, so VoiceOver does not read each badge
    /// separately as unlabelled noise.
    private var accessibilityDescription: String {
        var parts = [chat.title]
        if chat.unreadCount > 0 { parts.append("\(chat.unreadCount) unread") }
        if chat.hasDraft { parts.append("has draft") }
        if chat.isMuted { parts.append("muted") }
        if !previewText.isEmpty { parts.append(previewText) }
        return parts.joined(separator: ", ")
    }
}

struct UnreadBadge: View {
    let count: Int
    let isMuted: Bool

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(isMuted ? Theme.tertiaryText : Theme.accent, in: Capsule())
    }
}

/// Intelligent, locale-aware time formatting (brief §66).
public enum RelativeTimeFormatter {
    public static func short(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        // Within the last week, the weekday is more useful than a date.
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    /// The exact value, shown on hover (brief §66).
    public static func exact(_ date: Date) -> String {
        date.formatted(date: .complete, time: .standard)
    }
}
