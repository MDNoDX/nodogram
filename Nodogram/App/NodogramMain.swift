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

    @AppStorage(BackgroundSettings.menuBarIconKey) private var showsMenuBarIcon = true

    var body: some Scene {
        WindowGroup("Nodogram", id: "main") {
            MainWindowView(model: .shared)
        }
        // Content-sized minimums; the window frame itself is restored by macOS.
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands { NodogramCommands() }

        MenuBarExtra(isInserted: $showsMenuBarIcon) {
            MenuBarContent(model: .shared)
        } label: {
            MenuBarLabel(model: .shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false

    /// Closing the window keeps Nodogram running in the menu bar (unless the
    /// user turned that off), so updates keep arriving.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !BackgroundSettings.keepRunning
    }

    /// TDLib must be closed before the process ends. Once it reports closed,
    /// the process exits without running C++ static destructors, which would
    /// otherwise race TDLib's receive thread and crash on the way out.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        let model = AppModel.shared
        isTerminating = true
        Task { @MainActor in
            await model.shutdownAndWait()
            UserDefaults.standard.synchronize()
            _exit(0)
        }
        return .terminateLater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A messenger belongs in the Dock. It does not force itself to the
        // front: macOS already activates an app the user opens, and stealing
        // focus from whatever they are doing is never acceptable.
        NSApp.setActivationPolicy(.regular)
    }
}
