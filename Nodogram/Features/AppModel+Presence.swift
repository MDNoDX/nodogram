//  Online status and running in the background.
//
//  Online follows what the user is doing, as in the official apps: online
//  while Nodogram is the active app, offline shortly after it is not. While
//  in the background — window closed, menu bar only — Nodogram stays
//  connected and keeps receiving updates (deletions, typing, story views), but
//  the user shows as offline, because they are.

import AppKit
import Foundation
import NodogramDomain
import NodogramTelegram

public enum BackgroundSettings {
    /// Keep running in the menu bar when the window is closed.
    public static let keepRunningKey = "general.keepRunningInBackground"
    public static let menuBarIconKey = "general.menuBarIcon"

    public static var keepRunning: Bool { UserDefaults.standard.object(forKey: keepRunningKey) as? Bool ?? true }
}

extension AppModel {

    func startPresenceTracking() {
        guard presenceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        presenceObservers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        })
        presenceObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appResignedActive(after: .seconds(15)) }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            presenceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appResignedActive(after: .zero) }
            })
        }
        if NSApp.isActive { appBecameActive() }
    }

    private func appBecameActive() {
        offlineTask?.cancel()
        offlineTask = nil
        guard let gateway else { return }
        Task { await gateway.setOnline(true) }
    }

    private func appResignedActive(after delay: Duration) {
        offlineTask?.cancel()
        offlineTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let gateway = self?.gateway else { return }
            await gateway.setOnline(false)
        }
    }
}
