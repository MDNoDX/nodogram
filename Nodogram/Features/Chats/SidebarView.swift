//  Navigation sidebar.

import SwiftUI
import NodogramUI
import NodogramDomain

public struct SidebarView: View {
    @Binding private var selection: SidebarDestination
    private let connectionState: ConnectionState
    private let unreadTotal: Int
    private let draftCount: Int
    private let onSignOut: () -> Void

    public init(
        selection: Binding<SidebarDestination>,
        connectionState: ConnectionState,
        unreadTotal: Int,
        draftCount: Int,
        onSignOut: @escaping () -> Void
    ) {
        self._selection = selection
        self.connectionState = connectionState
        self.unreadTotal = unreadTotal
        self.draftCount = draftCount
        self.onSignOut = onSignOut
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(SidebarDestination.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.destinations) { destination in
                        Label(destination.title, systemImage: destination.icon)
                            .badge(badge(for: destination))
                            .tag(destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if connectionState.isWorthShowing {
                    ConnectionBadge(state: connectionState)
                        .padding(.vertical, 6)
                }
                Divider()
                Button(role: .destructive, action: onSignOut) {
                    Label(L10n.signOut, systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(.bar)
        }
    }

    private func badge(for destination: SidebarDestination) -> Int {
        switch destination {
        case .allChats: return unreadTotal
        case .drafts: return draftCount
        default: return 0
        }
    }
}
