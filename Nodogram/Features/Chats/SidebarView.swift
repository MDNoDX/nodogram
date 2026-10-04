//  Navigation sidebar: a compact rail of icons, like Telegram's folder bar.
//  "All Chats" and the user's Telegram folders come first, then the built-in
//  sections the user chose to show. Right-click any item to hide it or edit
//  the folder; Settings → Sidebar arranges the rest.

import SwiftUI
import NodogramUI
import NodogramDomain

public struct SidebarView: View {
    let model: AppModel
    let onSignOut: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    RailButton(title: SidebarDestination.allChats.title,
                               icon: SidebarDestination.allChats.icon,
                               selectedIcon: "bubble.left.and.bubble.right.fill",
                               isSelected: model.selectedDestination == .allChats && model.selectedFolderID == nil,
                               badge: model.unreadTotal) {
                        model.selectedDestination = .allChats
                    }

                    ForEach(model.visibleFolders) { folder in
                        RailButton(title: folder.title, icon: FolderIcon.symbol(for: folder.iconName),
                                   selectedIcon: FolderIcon.symbol(for: folder.iconName) + ".fill",
                                   isSelected: model.selectedFolderID == folder.id,
                                   badge: model.unreadCount(inFolder: folder.id)) {
                            model.selectFolder(folder.id)
                        }
                        .contextMenu {
                            Button("Edit Folder…") { openSettings(.folderEditor(folder.id)) }
                            Button("Hide from Sidebar") { model.setHidden("folder:\(folder.id)", true) }
                            Divider()
                            Button("Customize Sidebar…") { openSettings(.sidebar) }
                        }
                    }

                    let destinations = model.visibleRailDestinations.filter { $0 != .allChats }
                    if !destinations.isEmpty {
                        Divider().frame(width: 34).padding(.vertical, 6)
                    }
                    ForEach(destinations) { destination in
                        RailButton(title: destination.title, icon: destination.icon,
                                   selectedIcon: destination.filledIcon,
                                   isSelected: model.selectedDestination == destination && model.selectedFolderID == nil,
                                   badge: badge(for: destination)) {
                            model.selectedDestination = destination
                        }
                        .contextMenu {
                            Button("Hide from Sidebar") { model.setHidden(destination.rawValue, true) }
                            Divider()
                            Button("Customize Sidebar…") { openSettings(.sidebar) }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            VStack(spacing: 2) {
                if model.connectionState.isWorthShowing {
                    Group {
                        if model.connectionState == .offline {
                            Image(systemName: "wifi.slash").foregroundStyle(Theme.failure)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .help(connectionLabel)
                    .accessibilityLabel(connectionLabel)
                    .padding(.bottom, 6)
                }
                Divider().frame(width: 34).padding(.bottom, 4)
                RailButton(title: SidebarDestination.settings.title, icon: "gearshape",
                           selectedIcon: "gearshape.fill",
                           isSelected: model.selectedDestination == .settings, badge: 0) {
                    model.selectedDestination = .settings
                }
                Button(action: onSignOut) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.signOut)
                .accessibilityLabel(L10n.signOut)
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Customize Sidebar…") { openSettings(.sidebar) }
            Button("Chat Folders…") { openSettings(.folders) }
        }
    }

    private func openSettings(_ page: SettingsPage) {
        model.settingsPage = page
        model.selectedDestination = .settings
    }

    private var connectionLabel: String {
        switch model.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .connectingToProxy: return "Connecting to proxy…"
        case .updating: return "Updating…"
        case .offline: return "Waiting for network…"
        }
    }

    private func badge(for destination: SidebarDestination) -> Int {
        switch destination {
        case .unread: return model.chatsByID.values.filter { $0.order != 0 && $0.appearsUnread && !$0.isMuted }.count
        case .drafts: return model.draftCount
        case .localArchive: return model.unseenDeletedCount
        case .typingLog: return model.unseenTypingCount
        default: return 0
        }
    }
}

private struct RailButton: View {
    let title: String
    let icon: String
    let selectedIcon: String
    let isSelected: Bool
    let badge: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Group {
                    if let emoji = leadingEmoji {
                        // Folders named with an emoji show it as their icon.
                        Text(emoji).font(.system(size: 19))
                    } else {
                        Image(systemName: isSelected ? resolvedSelectedIcon : icon)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    }
                }
                .frame(height: 22)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 999 ? "999+" : "\(badge)")
                            .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 13, y: -6)
                            .fixedSize()
                    }
                }
                Text(labelText)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
            .frame(width: 64, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Theme.accent.opacity(0.14) : (isHovered ? Color.primary.opacity(0.06) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The emoji a folder name starts with ("🌙 Islam" → "🌙"), if any.
    private var leadingEmoji: String? {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return nil }
        let scalars = first.unicodeScalars
        guard let head = scalars.first, head.properties.isEmoji,
              head.properties.isEmojiPresentation || scalars.count > 1 || head.value > 0x2000 else { return nil }
        return String(first)
    }

    /// The name without its leading emoji; empty names fall back to it.
    private var labelText: String {
        guard leadingEmoji != nil else { return title }
        let rest = title.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? " " : rest
    }

    /// Not every symbol has a filled variant; fall back to the outline.
    private var resolvedSelectedIcon: String {
        NSImage(systemSymbolName: selectedIcon, accessibilityDescription: nil) != nil ? selectedIcon : icon
    }
}

extension SidebarDestination {
    var filledIcon: String {
        switch self {
        case .allChats: return "bubble.left.and.bubble.right.fill"
        case .personal: return "person.fill"
        case .groups: return "person.2.fill"
        case .channels: return "megaphone.fill"
        case .saved: return "bookmark.fill"
        case .archived: return "archivebox.fill"
        case .starred: return "star.fill"
        case .files: return "doc.fill"
        case .settings: return "gearshape.fill"
        default: return icon
        }
    }
}
