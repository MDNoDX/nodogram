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
