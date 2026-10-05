//  App lock: Touch ID (or the Mac's password) before chats are shown — at
//  launch, after the Mac sleeps, and after a chosen time away.

import AppKit
import LocalAuthentication
import SwiftUI
import NodogramUI

public enum AppLockSettings {
    public static let enabledKey = "lock.enabled"
    /// Minutes away before locking; 0 = only at launch and on sleep.
    public static let afterKey = "lock.afterMinutes"

    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    public static var afterMinutes: Int { UserDefaults.standard.object(forKey: afterKey) as? Int ?? 5 }
}

extension AppModel {

    func startAppLock() {
        guard lockObservers.isEmpty else { return }
        isLocked = AppLockSettings.isEnabled
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            lockObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if AppLockSettings.isEnabled { self?.isLocked = true } }
            })
        }
        lockObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lastActiveAt = Date() }
        })
        lockObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AppLockSettings.isEnabled, AppLockSettings.afterMinutes > 0,
                      let away = self.lastActiveAt,
                      Date().timeIntervalSince(away) > Double(AppLockSettings.afterMinutes * 60) else { return }
                self.isLocked = true
            }
        })
    }

    public func lockNow() {
        guard AppLockSettings.isEnabled else { return }
        isLocked = true
    }

    /// Asks for Touch ID, falling back to the Mac's login password.
    public func unlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No way to authenticate (no password set): do not lock the user out.
            isLocked = false
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock Nodogram") { ok, _ in
            Task { @MainActor [weak self] in if ok { self?.isLocked = false } }
        }
    }
}

struct LockScreen: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text("Nodogram is locked").font(.title2.weight(.semibold))
                Button {
                    model.unlock()
                } label: {
                    Label("Unlock with Touch ID", systemImage: "touchid").padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { model.unlock() }
    }
}
