//  Navigation sidebar.

import SwiftUI
import NodogramUI
import NodogramDomain

public struct SidebarView: View {
    @Binding private var selection: SidebarDestination
    private let connectionState: ConnectionState

    public init(selection: Binding<SidebarDestination>, connectionState: ConnectionState) {
        self._selection = selection
        self.connectionState = connectionState
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(SidebarDestination.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.destinations) { destination in
                        Label(destination.title, systemImage: destination.icon)
                            .tag(destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // Connection state lives here rather than over the conversation,
            // where it would compete with the message the user is reading.
            if connectionState.isWorthShowing {
                ConnectionBadge(state: connectionState)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}
