//  Navigation sidebar: a compact rail of icons, like Telegram's folder bar,
//  so the chat list and conversation get the width. Titles sit under each
//  icon in small type and in the tooltip.

import SwiftUI
import NodogramUI
import NodogramDomain

public struct SidebarView: View {
    @Binding private var selection: SidebarDestination
    private let connectionState: ConnectionState
    private let unreadTotal: Int
    private let unreadChats: Int
    private let draftCount: Int
    private let starredCount: Int
    private let onSignOut: () -> Void

    public init(
        selection: Binding<SidebarDestination>,
        connectionState: ConnectionState,
        unreadTotal: Int,
        unreadChats: Int = 0,
        draftCount: Int,
        starredCount: Int = 0,
        onSignOut: @escaping () -> Void
    ) {
        self._selection = selection
        self.connectionState = connectionState
        self.unreadTotal = unreadTotal
        self.unreadChats = unreadChats
        self.draftCount = draftCount
        self.starredCount = starredCount
        self.onSignOut = onSignOut
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(SidebarDestination.Group.allCases.enumerated()), id: \.element) { index, group in
                        if index > 0 {
                            Divider().frame(width: 34).padding(.vertical, 6)
                        }
                        ForEach(group.destinations.filter { $0 != .settings }) { destination in
                            RailButton(destination: destination, isSelected: selection == destination,
                                       badge: badge(for: destination)) {
                                selection = destination
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            VStack(spacing: 2) {
                if connectionState.isWorthShowing {
                    Group {
                        if connectionState == .offline {
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
                RailButton(destination: .settings, isSelected: false, badge: 0) { selection = .settings }
                Button(action: onSignOut) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.signOut)
                .accessibilityLabel(L10n.signOut)
            }
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var connectionLabel: String {
        switch connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .connectingToProxy: return "Connecting to proxy…"
        case .updating: return "Updating…"
        case .offline: return "Waiting for network…"
        }
    }

    private func badge(for destination: SidebarDestination) -> Int {
        switch destination {
        case .allChats: return unreadTotal
        case .unread: return unreadChats
        case .drafts: return draftCount
        case .starred: return starredCount
        default: return 0
        }
    }
}

private struct RailButton: View {
    let destination: SidebarDestination
    let isSelected: Bool
    let badge: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? filledIcon : destination.icon)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .frame(height: 22)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 999 ? "999+" : "\(badge)")
                                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Theme.accent, in: Capsule())
                                .offset(x: 12, y: -6)
                                .fixedSize()
                        }
                    }
                Text(destination.title)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
        .help(helpText)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var helpText: String {
        if let index = destination.keyboardShortcutIndex { return "\(destination.title)  ⌘\(index)" }
        return destination.title
    }

    private var filledIcon: String {
        switch destination {
        case .allChats: return "bubble.left.and.bubble.right.fill"
        case .personal: return "person.fill"
        case .groups: return "person.2.fill"
        case .channels: return "megaphone.fill"
        case .saved: return "bookmark.fill"
        case .archived: return "archivebox.fill"
        case .starred: return "star.fill"
        case .files: return "doc.fill"
        case .settings: return "gearshape.fill"
        default: return destination.icon
        }
    }
}
