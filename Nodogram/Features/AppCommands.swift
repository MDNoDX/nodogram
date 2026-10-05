//  Menu bar commands, wired to the focused window's model.

import AppKit
import SwiftUI
import NodogramDomain

public struct AppModelFocusKey: FocusedValueKey {
    public typealias Value = AppModel
}

extension FocusedValues {
    public var appModel: AppModel? {
        get { self[AppModelFocusKey.self] }
        set { self[AppModelFocusKey.self] = newValue }
    }
}

/// Every command carries its shortcut, so the menu doubles as documentation
/// for the keyboard model. Commands that need a chat are disabled without one.
public struct NodogramCommands: Commands {
    @FocusedValue(\.appModel) private var model

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model?.selectedDestination = .settings }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(model == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button("Quick Open…") { model?.isPaletteVisible = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil)
        }

        CommandMenu("Account") {
            if let model {
                let _ = model.accountsVersion
                ForEach(model.accountIDs, id: \.self) { id in
                    Button((id == model.activeAccountID ? "✓ " : "") + Accounts.name(id)) { model.switchAccount(to: id) }
                }
                Divider()
                Button("Add Account…") { model.addAccount() }
                Button("Lock Now") { model.lockNow() }
                    .keyboardShortcut("l", modifiers: [.command, .control])
            }
        }

        CommandMenu("Chat") {
            Button("Find in Conversation…") { model?.beginConversationSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(chat == nil)
            Divider()
            Button(isUnread ? "Mark as Read" : "Mark as Unread") {
                guard let model, let chat else { return }
                if isUnread { model.markAsRead(chat.id) } else { model.setMarkedUnread(true, chat: chat.id) }
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(chat == nil)
            Button(chat?.isPinned == true ? "Unpin" : "Pin") {
                guard let model, let chat else { return }
                model.setPinned(!chat.isPinned, chat: chat.id)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(chat == nil)
            Button(chat?.isMuted == true ? "Unmute" : "Mute") {
                guard let model, let chat else { return }
                model.setMuted(!chat.isMuted, chat: chat.id)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(chat == nil)
            Button(model?.selectedDestination == .archived ? "Unarchive" : "Archive") {
                guard let model, let chat else { return }
                model.setArchived(model.selectedDestination != .archived, chat: chat.id)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(chat == nil || chat?.isSavedMessages == true)
            Divider()
            Button("Jump to Latest") { model?.returnToLatest() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(model?.hasNewerHistory != true)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Streamer Mode") {
                let key = "privacy.streamerMode"
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
                model?.showToast(UserDefaults.standard.bool(forKey: key) ? "Streamer mode on" : "Streamer mode off")
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandMenu("Go") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model?.canGoBack != true)
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model?.canGoForward != true)
            Divider()
            ForEach(SidebarDestination.allCases.filter { $0 != .settings }) { destination in
                if let index = destination.keyboardShortcutIndex {
                    Button(destination.title) { model?.selectedDestination = destination }
                        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                } else {
                    Button(destination.title) { model?.selectedDestination = destination }
                }
            }
            .disabled(model == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Nodogram on GitHub") {
                if let url = URL(string: "https://github.com/MDNoDX/nodogram") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var chat: Chat? { model?.selectedChat }
    private var isUnread: Bool { (chat?.unreadCount ?? 0) > 0 || chat?.isMarkedAsUnread == true }
}
