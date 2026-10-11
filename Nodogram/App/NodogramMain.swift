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
        WindowGroup("Nodogram", id: "main") {
            MainWindowView(model: .shared)
        }
        // Content-sized minimums; the window frame itself is restored by macOS.
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        // Always open the window at launch, even when the last session ended
        // with it closed (Nodogram then lived in the menu bar).
        .defaultLaunchBehavior(.presented)
        .commands { NodogramCommands() }

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isTerminating = false
    private let statusItem = StatusItemController()
    private var defaultsObserver: NSObjectProtocol?

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

    /// Clicking the Dock icon (or reopening) always brings a window back,
    /// even when the app was running window-less in the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.contentView != nil && $0.styleMask.contains(.titled) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window exists: ask SwiftUI to open the main scene.
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A messenger belongs in the Dock. It does not force itself to the
        // front: macOS already activates an app the user opens, and stealing
        // focus from whatever they are doing is never acceptable.
        NSApp.setActivationPolicy(.regular)
        updateStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if !NSApp.windows.contains(where: { $0.styleMask.contains(.titled) && $0.isVisible }) { self?.showMainWindow() }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusItem() }
        }
    }

    func updateStatusItem() {
        let show = UserDefaults.standard.object(forKey: BackgroundSettings.menuBarIconKey) as? Bool ?? true
        if show { statusItem.install() } else { statusItem.remove() }
    }
}
