//  The main three-pane window.
//
//  Layout follows the brief §4: sidebar | conversation list | conversation.
//  `NavigationSplitView` gives native macOS behaviour — draggable dividers,
//  collapsible columns, and automatic state restoration — rather than a
//  hand-rolled layout that would only approximate it.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct MainWindowView: View {
    @State private var model = AppModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {}

    public var body: some View {
        Group {
            switch model.phase {
            case .loadingCredentials:
                ProgressView()
                    .controlSize(.small)
                    .frame(minWidth: 460, minHeight: 300)

            case .needsCredentials(let detail):
                SetupView(detail: detail) {
                    Task { await model.start() }
                }

            case .authenticating(let state):
                AuthenticationView(
                    state: state,
                    errorMessage: model.authErrorMessage,
                    isBusy: model.isBusy,
                    onSubmitPhone: model.submitPhoneNumber,
                    onSubmitCode: model.submitCode,
                    onSubmitPassword: model.submitPassword
                )

            case .ready:
                mainLayout
            }
        }
        .task {
            // Only start once; re-entry is handled by the setup screen's button.
            if case .loadingCredentials = model.phase {
                await model.start()
            }
        }
        .onReceive(of: NSApplication.willTerminateNotification) {
            // TDLib requires clients be closed before termination.
            model.shutdown()
        }
    }

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selection: Binding(
                    get: { model.selectedDestination },
                    set: { model.selectedDestination = $0 }
                ),
                connectionState: model.connectionState
            )
            .navigationSplitViewColumnWidth(
                min: Theme.Metrics.sidebarMinWidth,
                ideal: Theme.Metrics.sidebarIdealWidth
            )
        } content: {
            ChatListView(
                chats: model.chats,
                destination: model.selectedDestination,
                selectedChatID: Binding(
                    get: { model.selectedChatID },
                    set: { model.selectedChatID = $0 }
                ),
                searchText: Binding(
                    get: { model.searchText },
                    set: { model.searchText = $0 }
                )
            )
            .navigationSplitViewColumnWidth(
                min: Theme.Metrics.chatListMinWidth,
                ideal: Theme.Metrics.chatListIdealWidth
            )
        } detail: {
            ConversationView(
                chat: selectedChat,
                messages: selectedChat.flatMap { model.messages[$0.id] } ?? [],
                draftText: Binding(
                    get: { model.draftText },
                    set: {
                        model.draftText = $0
                        model.draftTextChanged()
                    }
                ),
                draftIndicatorVisible: model.draftIndicatorVisible,
                onSend: model.sendDraft
            )
            .frame(minWidth: Theme.Metrics.conversationMinWidth)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var selectedChat: Chat? {
        guard let id = model.selectedChatID else { return nil }
        return model.chats.first { $0.id == id }
    }
}

/// Small helper for observing an `NSNotification` from SwiftUI without
/// reaching for Combine.
private extension View {
    func onReceive(
        of name: Notification.Name,
        perform action: @escaping () -> Void
    ) -> some View {
        task {
            for await _ in NotificationCenter.default.notifications(named: name) {
                action()
            }
        }
    }
}
