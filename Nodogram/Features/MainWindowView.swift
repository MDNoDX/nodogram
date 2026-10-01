//  The main three-pane window: sidebar | conversation list | conversation.
//
//  `NavigationSplitView` provides native macOS behaviour — draggable dividers,
//  collapsible columns, toolbar title/subtitle — rather than a hand-rolled
//  layout that would only approximate it.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct MainWindowView: View {
    @State private var model = AppModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var confirmingSignOut = false

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
                    .overlay { MediaViewerOverlay(model: model) }
                    .animation(.easeOut(duration: 0.15), value: model.viewerMessageID)
            }
        }
        .task {
            if case .loadingCredentials = model.phase {
                await model.start()
            }
        }
        .onAppear {
            // Consecutive voice messages play one after another, like Telegram.
            AudioPlayback.shared.onFinished = { [model] finished in
                guard let index = model.messages.firstIndex(where: { $0.id == finished }) else { return }
                let next = model.messages[(index + 1)...].first { message in
                    if case .voiceNote = message.media { return !message.isDeleted }
                    return false
                }
                if let next, case .voiceNote(let voice) = next.media {
                    AudioPlayback.shared.start(next, file: voice.file) { await model.fetch($0, priority: 32) }
                } else {
                    AudioPlayback.shared.stop()
                }
            }
        }
        .task {
            // TDLib requires clients be closed before termination.
            for await _ in NotificationCenter.default.notifications(named: NSApplication.willTerminateNotification) {
                model.shutdown()
            }
        }
        .confirmationDialog(
            "Sign out of Nodogram?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button(L10n.signOut, role: .destructive) { model.signOut() }
        } message: {
            Text("This ends the session on this Mac. Your chats stay on Telegram.")
        }
    }

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selection: Binding(
                    get: { model.selectedDestination },
                    set: { model.selectedDestination = $0 }
                ),
                connectionState: model.connectionState,
                unreadTotal: model.unreadTotal,
                draftCount: model.draftCount,
                onSignOut: { confirmingSignOut = true }
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
        } content: {
            ChatListView(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
        } detail: {
            ConversationView(model: model)
                .frame(minWidth: Theme.Metrics.conversationMinWidth)
        }
        .navigationSplitViewStyle(.balanced)
    }
}
