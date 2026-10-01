//  Nodogram — application entry point.
//
//  Nodogram is an independent, unofficial Telegram client. It is not
//  affiliated with, endorsed by, or sponsored by Telegram Messenger LLP, and
//  uses no Telegram branding. See Documentation/LEGAL_AND_LICENSES.md §5.

import SwiftUI
import AppKit
import NodogramFeatures
import NodogramUI

@main
struct NodogramMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        // Content-sized minimums; the window frame itself is restored by macOS.
        .defaultSize(width: 1180, height: 760)
        .commands { NodogramCommands() }

        Settings {
            SettingsView()
        }
    }
}

/// Menu bar commands. Every one carries its shortcut, so the menu doubles as
/// discoverable documentation for the keyboard model (brief §20, §21).
struct NodogramCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Message") {}
                .keyboardShortcut("n", modifiers: .command)
            Button("New Group") {}
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Chat") {
            Button("Search Chats…") {}
                .keyboardShortcut("k", modifiers: .command)
            Button("Find in Conversation…") {}
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Mark Unread") {}
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Mute") {}
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Archive") {}
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Button("Nodogram Documentation") {
                if let url = URL(string: "https://github.com/MDNoDX/nodogram") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A messenger belongs in the Dock. It does not force itself to the
        // front: macOS already activates an app the user opens, and stealing
        // focus from whatever they are doing is never acceptable.
        NSApp.setActivationPolicy(.regular)
    }
}
