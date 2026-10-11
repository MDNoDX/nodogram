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

        // A light menu bar item: a static icon (no reactive binding, so no
        // render loop) whose menu can reopen the window and captures the
        // openWindow action for the Dock-reopen path.
        MenuBarExtra {
            Button("Open Nodogram") { WindowOpener.shared.show() }
            Divider()
            Button("Settings…") { AppModel.shared.selectedDestination = .settings; WindowOpener.shared.show() }
            Button("Quit Nodogram") { NSApp.terminate(nil) }
        } label: {
            // A plain icon captures the openWindow action (needed to reopen a
            // closed window) without binding to any observable, so no render loop.
            MenuBarLabel()
        }
    }
}

/// The static menu bar icon; records how to open the main window.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: "bubble.left.and.text.bubble.right")
            .onAppear { WindowOpener.shared.open = { openWindow(id: "main") } }
    }
}

/// Holds the SwiftUI openWindow action so AppKit paths (Dock reopen) can
/// bring the window back when none exists.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var open: (() -> Void)?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            open?()
        }
    }

    /// Keeps trying until a real window exists — the opener action may not be
    /// captured the instant the app launches window-less.
    func ensureWindow(attempt: Int = 0) {
        if NSApp.windows.contains(where: { $0.styleMask.contains(.titled) && $0.canBecomeMain && ($0.frame.height > 200) }) { return }
        show()
        guard attempt < 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.ensureWindow(attempt: attempt + 1) }
    }
}

@MainActor
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

    /// Clicking the Dock icon (or reopening) always brings a window back,
    /// even when the app was running window-less in the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowOpener.shared.show() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A messenger belongs in the Dock. It does not force itself to the
        // front: macOS already activates an app the user opens, and stealing
        // focus from whatever they are doing is never acceptable.
        NSApp.setActivationPolicy(.regular)
        // Ensure a window is visible shortly after launch (retries, since the
        // opener action is captured once the menu bar label renders).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { WindowOpener.shared.ensureWindow() }
    }

}
