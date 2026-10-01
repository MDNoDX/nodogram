//  Navigation sidebar model.
//
//  The brief enumerates the required destinations (brief §5). Modelling them as
//  an enum keeps the sidebar, the command palette, and keyboard shortcuts
//  working from one source of truth instead of three parallel lists.

import Foundation
import NodogramUI

public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allChats, unread, personal, groups, channels, saved
    case archived, drafts
    case media, files, links, voiceMessages
    case starred, recentlyViewed, localArchive
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allChats: return L10n.allChats
        case .unread: return L10n.unread
        case .personal: return L10n.personal
        case .groups: return L10n.groups
        case .channels: return L10n.channels
        case .saved: return L10n.saved
        case .archived: return L10n.archived
        case .drafts: return L10n.drafts
        case .media: return L10n.media
        case .files: return L10n.files
        case .links: return L10n.links
        case .voiceMessages: return L10n.voiceMessages
        case .starred: return L10n.starred
        case .recentlyViewed: return L10n.recentlyViewed
        case .localArchive: return L10n.localArchive
        case .settings: return L10n.settings
        }
    }

    public var icon: String {
        switch self {
        case .allChats: return "bubble.left.and.bubble.right"
        case .unread: return "circle.badge.fill"
        case .personal: return "person"
        case .groups: return "person.2"
        case .channels: return "megaphone"
        case .saved: return "bookmark"
        case .archived: return "archivebox"
        case .drafts: return "square.and.pencil"
        case .media: return "photo.on.rectangle"
        case .files: return "doc"
        case .links: return "link"
        case .voiceMessages: return "waveform"
        case .starred: return "star"
        case .recentlyViewed: return "clock"
        case .localArchive: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// Sidebar groups, which the brief wants collapsible (brief §5).
    public enum Group: String, CaseIterable, Identifiable, Sendable {
        case conversations, organize, content, local

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .conversations: return "Chats"
            case .organize: return "Organize"
            case .content: return "Content"
            case .local: return "Local"
            }
        }

        public var destinations: [SidebarDestination] {
            switch self {
            case .conversations: return [.allChats, .unread, .personal, .groups, .channels, .saved]
            case .organize: return [.archived, .drafts, .starred, .recentlyViewed]
            case .content: return [.media, .files, .links, .voiceMessages]
            case .local: return [.localArchive, .settings]
            }
        }
    }

    /// Only the first nine get ⌘1–9, per the brief's "where practical".
    public var keyboardShortcutIndex: Int? {
        let shortcutable: [SidebarDestination] = [
            .allChats, .unread, .personal, .groups, .channels,
            .saved, .archived, .drafts, .starred,
        ]
        guard let index = shortcutable.firstIndex(of: self) else { return nil }
        return index + 1
    }
}
