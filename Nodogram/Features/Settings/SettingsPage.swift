//  Settings pages, listed like Telegram's.

import Foundation

public enum SettingsPage: Hashable, Sendable {
    case profile, general, notifications, privacy, dataStorage, sessions, appearance, language
    case folders, folderEditor(Int?), sidebar
    case nodogramFeatures, filters, about

    public var title: String {
        switch self {
        case .profile: return "My Profile"
        case .general: return "General"
        case .notifications: return "Notifications and Sounds"
        case .privacy: return "Privacy and Security"
        case .dataStorage: return "Data and Storage"
        case .sessions: return "Active Sessions"
        case .appearance: return "Appearance"
        case .language: return "Language"
        case .filters: return "Message Filters"
        case .folders: return "Chat Folders"
        case .folderEditor(let id): return id == nil ? "New Folder" : "Edit Folder"
        case .sidebar: return "Sidebar"
        case .nodogramFeatures: return "Nodogram Features"
        case .about: return "About Nodogram"
        }
    }

    public var symbol: String {
        switch self {
        case .profile: return "person.crop.circle.fill"
        case .general: return "gearshape.fill"
        case .notifications: return "bell.badge.fill"
        case .privacy: return "lock.fill"
        case .dataStorage: return "externaldrive.fill"
        case .sessions: return "laptopcomputer.and.iphone"
        case .appearance: return "paintbrush.fill"
        case .language: return "globe"
        case .filters: return "line.3.horizontal.decrease.circle.fill"
        case .folders, .folderEditor: return "folder.fill"
        case .sidebar: return "sidebar.left"
        case .nodogramFeatures: return "sparkles"
        case .about: return "info.circle.fill"
        }
    }

    /// Icon tile colour, as Telegram colours each row.
    public var tint: (Double, Double, Double) {
        switch self {
        case .profile: return (0.93, 0.27, 0.36)
        case .general: return (0.55, 0.56, 0.60)
        case .notifications: return (0.95, 0.30, 0.25)
        case .privacy: return (0.20, 0.52, 0.96)
        case .dataStorage: return (0.20, 0.75, 0.40)
        case .sessions: return (0.98, 0.58, 0.10)
        case .appearance: return (0.18, 0.64, 0.98)
        case .language: return (0.68, 0.40, 0.95)
        case .filters: return (0.95, 0.45, 0.20)
        case .folders, .folderEditor: return (0.42, 0.45, 0.95)
        case .sidebar: return (0.35, 0.70, 0.85)
        case .nodogramFeatures: return (0.68, 0.35, 0.95)
        case .about: return (0.50, 0.55, 0.62)
        }
    }

    /// Rows in the settings list, grouped as Telegram groups them.
    public static let groups: [[SettingsPage]] = [
        [.profile],
        [.general, .notifications, .privacy, .dataStorage, .sessions, .appearance, .language],
        [.folders, .sidebar],
        [.nodogramFeatures, .filters],
        [.about],
    ]

    /// The page a sub-page returns to with the back button.
    public var parent: SettingsPage? {
        switch self {
        case .folderEditor: return .folders
        default: return nil
        }
    }
}
