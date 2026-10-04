//  Conversation list.
//
//  Rows use hierarchical styles (.primary / .secondary) rather than fixed
//  colours, so they stay legible inside macOS's own selection highlight.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ChatListView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let chats = model.visibleChats

        Group {
            if !model.destinationIsChatList {
                LibrarySectionView(model: model)
            } else if chats.isEmpty {
                if model.isLoadingChats || (model.chatsByID.isEmpty && model.searchText.isEmpty) {
                    LoadingChatsView()
                } else {
                    EmptyStateView(
                        icon: model.searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                        title: model.searchText.isEmpty ? emptyTitle : L10n.noSearchResults,
                        message: model.searchText.isEmpty ? emptyMessage : "No chat matches “\(model.searchText)”."
                    )
                }
            } else {
                List(selection: Binding(get: { model.selectedChatID }, set: { model.select($0) })) {
                    ForEach(chats) { chat in
                        ChatRow(chat: chat, activity: model.activityText(for: chat.id),
                                hasStories: model.storyOwners[chat.id]?.hasUnread == true)
                            .tag(chat.id)
                            .contextMenu { ChatMenu(model: model, chat: chat) }
                            .onAppear {
                                model.ensureAvatar(for: chat.id)
                                // Page in more chats as the end comes into view.
                                if chat.id == chats.last?.id {
                                    model.loadMoreChats(in: model.selectedDestination == .archived ? .archive : .main)
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if model.selectedDestination == .allChats, model.searchText.isEmpty {
                        StoriesStrip(model: model)
                    }
                }
            }
        }
        .navigationTitle(model.selectedDestination.title)
        .searchable(
            text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
            placement: .toolbar,
            prompt: "Search chats"
        )
    }

    private var emptyTitle: String {
        switch model.selectedDestination {
        case .unread: return "You're all caught up"
        case .drafts: return "No drafts"
        case .archived: return "Archive is empty"
        case .saved: return "Saved Messages"
        default: return L10n.noChatsTitle
        }
    }

    private var emptyMessage: String {
        switch model.selectedDestination {
        case .unread: return "Chats with unread messages appear here."
        case .drafts: return "Start typing in any chat and it appears here, so nothing half-written gets lost."
        case .archived: return "Chats you archive in Telegram appear here."
        case .saved: return "Your Saved Messages chat appears here once it has loaded."
        case .personal: return "One-to-one chats appear here."
        case .groups: return "Group chats appear here."
        case .channels: return "Channels you follow appear here."
        default: return L10n.noChatsBody
        }
    }
}

struct ChatRow: View {
    let chat: Chat
    /// "typing…" — shown in place of the preview, as Telegram does.
    let activity: String?
    /// Unseen stories: the avatar gets a ring, as in Telegram.
    var hasStories = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(
                title: chat.title,
                seed: chat.id.rawValue,
                imagePath: chat.avatarPath,
                thumbnail: chat.avatarThumbnail,
                isOnline: chat.presence == .online,
                isSavedMessages: chat.isSavedMessages
            )
            .overlay {
                if hasStories {
                    Circle().strokeBorder(Theme.accent, lineWidth: 2).padding(-3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(chat.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if chat.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Verified")
                    }
                    if chat.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Muted")
                    }

                    Spacer(minLength: 6)

                    if let date = chat.lastMessage?.date {
                        Text(RelativeTimeFormatter.short(date))
                            .font(.system(size: 11))
                            .foregroundStyle(chat.appearsUnread && !chat.isMuted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                            .help(RelativeTimeFormatter.exact(date))
                    }
                }

                HStack(alignment: .top, spacing: 6) {
                    preview
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    trailingBadges
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Draft first (it is the user's own unsent work), then the last message
    /// with its sender, then the attachment label for media.
    private var preview: Text {
        if let activity {
            return Text(activity).foregroundStyle(Theme.accent)
        }
        if let draft = chat.draftText, !draft.isEmpty {
            return Text("Draft: ").foregroundStyle(Theme.failure) + Text(draft).foregroundStyle(.secondary)
        }
        guard let last = chat.lastMessage else {
            return Text("No messages yet").foregroundStyle(.tertiary)
        }

        var result = Text("")
        if let sender = last.senderName, !sender.isEmpty {
            result = result + Text("\(sender): ").foregroundStyle(.primary)
        }
        if let label = last.attachmentLabel {
            let separator = last.text.isEmpty ? "" : " · "
            result = result + Text(label + separator).foregroundStyle(Theme.accent)
        }
        return result + Text(last.text).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var trailingBadges: some View {
        HStack(spacing: 4) {
            if chat.unreadMentionCount > 0 {
                Text("@")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .background(Theme.accent, in: Circle())
                    .accessibilityLabel("Mentioned")
            }

            if chat.unreadCount > 0 {
                Text(chat.unreadCount > 9_999 ? "9999+" : "\(chat.unreadCount)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(chat.isMuted ? AnyShapeStyle(Color.gray.opacity(0.6)) : AnyShapeStyle(Theme.accent), in: Capsule())
            } else if chat.isMarkedAsUnread {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 10, height: 10)
                    .padding(4)
                    .accessibilityLabel("Marked as unread")
            } else if chat.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(45))
                    .padding(.top, 2)
                    .accessibilityLabel("Pinned")
            }
        }
    }

    /// One spoken sentence, so VoiceOver does not read badges as noise.
    private var accessibilityDescription: String {
        var parts = [chat.title]
        if chat.unreadCount > 0 { parts.append("\(chat.unreadCount) unread") }
        if chat.unreadMentionCount > 0 { parts.append("mentioned") }
        if chat.hasDraft { parts.append("has a draft") }
        if chat.isMuted { parts.append("muted") }
        if chat.isPinned { parts.append("pinned") }
        if let last = chat.lastMessage {
            parts.append([last.senderName, last.displayText].compactMap { $0 }.joined(separator: ": "))
        }
        return parts.joined(separator: ", ")
    }
}

/// Right-click actions on a chat, as in Telegram.
struct ChatMenu: View {
    let model: AppModel
    let chat: Chat

    var body: some View {
        let isArchived = model.selectedDestination == .archived
        if chat.unreadCount > 0 || chat.isMarkedAsUnread {
            Button { model.markAsRead(chat.id) } label: { Label("Mark as Read", systemImage: "checkmark.message") }
        } else {
            Button { model.setMarkedUnread(true, chat: chat.id) } label: {
                Label("Mark as Unread", systemImage: "message.badge")
            }
        }
        Button { model.setPinned(!chat.isPinned, chat: chat.id) } label: {
            Label(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin")
        }
        Button { model.setMuted(!chat.isMuted, chat: chat.id) } label: {
            Label(chat.isMuted ? "Unmute" : "Mute", systemImage: chat.isMuted ? "bell" : "bell.slash")
        }
        if !chat.isSavedMessages {
            Button { model.setArchived(!isArchived, chat: chat.id) } label: {
                Label(isArchived ? "Unarchive" : "Archive", systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
            }
        }
        if model.storyOwners[chat.id] != nil {
            Divider()
            Button { model.openStories(from: chat.id) } label: { Label("View Stories", systemImage: "circle.dashed") }
        }
    }
}

/// Shape-matched placeholder, so the list does not jump when rows arrive.
private struct LoadingChatsView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { index in
                HStack(spacing: 10) {
                    Circle().fill(.quaternary).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                            .frame(width: CGFloat(90 + (index * 37) % 80), height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.7))
                            .frame(width: CGFloat(150 + (index * 53) % 70), height: 9)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            Spacer()
        }
        .padding(.top, 6)
        .accessibilityLabel("Loading chats")
    }
}
