//  The menu bar item. Nodogram keeps running here when its window is closed,
//  so deletions, typing and story views keep being recorded.
//
//  Plain AppKit on purpose: a SwiftUI MenuBarExtra re-rendered on every chat
//  update and could spin the main thread. This menu is built only when opened,
//  and the badge refreshes on a slow timer.

import AppKit
import NodogramDomain
import NodogramFeatures

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private var timer: Timer?

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "Nodogram")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        refreshBadge()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBadge() }
        }
    }

    func remove() {
        timer?.invalidate()
        timer = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func refreshBadge() {
        let model = AppModel.shared
        let count = model.unreadTotal
        let title = count > 0 ? " \(count)" : ""
        if item?.button?.title != title { item?.button?.title = title }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let model = AppModel.shared
        menu.removeAllItems()
        menu.addItem(action("Open Nodogram", key: "o") { Self.openWindow() })
        menu.addItem(.separator())
        menu.addItem(info(model.unreadTotal > 0 ? "\(model.unreadTotal) unread messages" : "No unread messages"))
        if model.unseenDeletedCount > 0 {
            menu.addItem(action("🗑 \(model.unseenDeletedCount) deleted messages kept") {
                model.selectedDestination = .localArchive
                Self.openWindow()
            })
        }
        if model.unseenTypingCount > 0 {
            menu.addItem(action("✍️ \(model.unseenTypingCount) people typed to you") {
                model.selectedDestination = .typingLog
                Self.openWindow()
            })
        }
        let recent = model.typingLog.prefix(3)
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(info("Recent typing"))
            for event in recent {
                let suffix = event.outcome == .abandoned ? " · didn't send" : ""
                menu.addItem(action("\(event.name) · \(event.startedAt.formatted(.dateTime.hour().minute()))\(suffix)") {
                    model.selectedDestination = .allChats
                    model.select(ChatID(event.chatID))
                    Self.openWindow()
                })
            }
        }
        if let vault = model.vaultStatus {
            menu.addItem(.separator())
            menu.addItem(info(vault.connected ? "Vault: connected · \(vault.deleted) deleted kept" : "Vault: not connected"))
        }
        menu.addItem(.separator())
        menu.addItem(action("Settings…", key: ",") {
            model.selectedDestination = .settings
            Self.openWindow()
        })
        menu.addItem(action("Quit Nodogram", key: "q") { NSApp.terminate(nil) })
    }

    /// Brings the window back; asking the app to reopen itself makes SwiftUI
    /// create a window when none is open.
    static func openWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.frame.height > 300 }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, key: String = "", _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
        return item
    }
}

@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("unused") }

    @objc private func run() { handler() }
}
