//  The main three-pane window: sidebar | conversation list | conversation.
//
//  `NavigationSplitView` provides native macOS behaviour — draggable dividers,
//  collapsible columns, toolbar title/subtitle — rather than a hand-rolled
//  layout that would only approximate it.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct MainWindowView: View {
    /// One model for the whole app, so Nodogram keeps receiving updates —
    /// typing, deletions, story views — while its window is closed.
    private let model: AppModel
    @AppStorage(Theme.colorSchemeKey) private var colorScheme = "system"
    @AppStorage(Theme.accentKey) private var accentIndex = 0
    @AppStorage(Theme.textSizeKey) private var textSize = 13.5
    @AppStorage(Theme.solidBubblesKey) private var solidBubbles = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var confirmingSignOut = false

    public init(model: AppModel = .shared) {
        self.model = model
    }

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

            case .storageLocked(let detail):
                VStack(spacing: 14) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("Nodogram needs Keychain access").font(.title2.weight(.semibold))
                    Text("""
                        Your chats are safe on this Mac. Nodogram is moving its key out of the Keychain so \
                        macOS stops asking for your password; it needs to read it there one last time. \
                        Click Try Again and, when macOS asks, enter your login password and choose “Allow”.
                        """)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 440)
                    Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: 440)
                    Button("Try Again") { Task { await model.start() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(40)
                .frame(minWidth: 560, minHeight: 380)

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
                    .overlay { StoryViewerOverlay(model: model) }
                    .overlay(alignment: .top) {
                        if model.isPaletteVisible {
                            ZStack(alignment: .top) {
                                Color.black.opacity(0.18).ignoresSafeArea()
                                    .onTapGesture { model.isPaletteVisible = false }
                                CommandPalette(model: model).padding(.top, 90)
                            }
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: model.viewerMessageID)
                    .animation(.easeOut(duration: 0.15), value: model.storyViewer)
                    .animation(.easeOut(duration: 0.12), value: model.isPaletteVisible)
                    .focusedSceneValue(\.appModel, model)
                    // Appearance changes redraw everything with the new tokens.
                    .id("appearance-\(accentIndex)-\(textSize)-\(solidBubbles)")
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(colorScheme == "light" ? .light : colorScheme == "dark" ? .dark : nil)
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
        .onAppear { AppModel.current = model }
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

    /// Mouse side buttons and a two-finger swipe go back and forward, as in
    /// Safari and Finder.
    private func installNavigationGestures() {
        guard !Self.gesturesInstalled else { return }
        Self.gesturesInstalled = true
        NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { event in
            let back: Bool?
            switch event.type {
            case .otherMouseDown where event.buttonNumber == 3: back = true
            case .otherMouseDown where event.buttonNumber == 4: back = false
            case .swipe where event.deltaX > 0: back = true
            case .swipe where event.deltaX < 0: back = false
            default: back = nil
            }
            guard let back else { return event }
            MainActor.assumeIsolated {
                let model = AppModel.shared
                if model.viewerMessageID != nil || model.storyViewer != nil { return }
                if back { model.goBack() } else { model.goForward() }
            }
            return nil
        }
    }

    @MainActor private static var gesturesInstalled = false

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model, onSignOut: { confirmingSignOut = true })
                .navigationSplitViewColumnWidth(78)
        } content: {
            Group {
                if model.selectedDestination == .settings {
                    SettingsListView(model: model)
                } else {
                    ChatListView(model: model)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
        } detail: {
            Group {
                if model.selectedDestination == .settings {
                    SettingsDetailView(model: model)
                } else {
                    ConversationView(model: model)
                }
            }
            .frame(minWidth: Theme.Metrics.conversationMinWidth)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .help("Back (⌘[)")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .help("Forward (⌘])")
            }
        }
        .onAppear(perform: installNavigationGestures)
        // Content-sized minimum: the window cannot be made smaller than what
        // fits, so nothing — the composer above all — is ever cut off.
        .frame(minWidth: 960, minHeight: 600)
    }
}
