//  The menu bar item: Nodogram keeps running here when its window is closed,
//  so nothing — a deletion, someone typing, a story view — is missed.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct MenuBarContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel = .shared) { self.model = model }

    public var body: some View {
        Button("Open Nodogram") { open(nil) }
            .keyboardShortcut("o")
        Divider()
        Text(model.unreadTotal > 0 ? "\(model.unreadTotal) unread messages" : "No unread messages")
        if model.unseenDeletedCount > 0 {
            Button("🗑 \(model.unseenDeletedCount) deleted messages kept") { open(.localArchive) }
        }
        if model.unseenTypingCount > 0 {
            Button("✍️ \(model.unseenTypingCount) people typed to you") { open(.typingLog) }
        }
        let recentTyping = model.typingLog.prefix(3)
        if !recentTyping.isEmpty {
            Divider()
            Text("Recent typing")
            ForEach(Array(recentTyping)) { event in
                Button("\(event.name) · \(event.startedAt.formatted(.dateTime.hour().minute()))"
                       + (event.outcome == .abandoned ? " · didn't send" : "")) {
                    model.select(ChatID(event.chatID))
                    open(.allChats)
                }
            }
        }
        Divider()
        Button("Settings…") { model.selectedDestination = .settings; open(nil) }
        Button("Quit Nodogram") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ destination: SidebarDestination?) {
        if let destination { model.selectedDestination = destination }
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// The icon in the menu bar, with the unread count beside it.
public struct MenuBarLabel: View {
    let model: AppModel
    public init(model: AppModel = .shared) { self.model = model }

    public var body: some View {
        let count = model.unreadTotal
        HStack(spacing: 2) {
            Image(systemName: count > 0 ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right")
            if count > 0 { Text("\(count)") }
        }
    }
}
