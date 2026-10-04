//  Marks downloaded files as coming from the internet.
//
//  macOS only runs Gatekeeper's checks on files carrying the
//  `com.apple.quarantine` attribute. TDLib does not set it, so without this an
//  app or script received in a chat would open with no check at all.

import AppKit
import Foundation

public enum Quarantine {

    /// Adds the quarantine attribute, as browsers do for downloads.
    public static func mark(_ path: String, origin: String = "Nodogram") {
        let flags = "0083"   // downloaded, user-approved-open not yet granted
        let timestamp = String(format: "%08x", Int(Date().timeIntervalSince1970))
        let value = "\(flags);\(timestamp);\(origin);"
        _ = value.withCString { pointer in
            setxattr(path, "com.apple.quarantine", pointer, strlen(pointer), 0, 0)
        }
    }

    public static func isMarked(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) > 0
    }

    /// File types that run code when opened.
    static let executableExtensions: Set<String> = [
        "app", "command", "sh", "pkg", "mpkg", "dmg", "scpt", "applescript", "workflow",
        "terminal", "tool", "jar", "py", "rb", "pl", "exe", "bat", "jsx",
    ]

    public static func isExecutable(_ path: String) -> Bool {
        executableExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Asks before opening a file that can run code.
    @MainActor
    public static func confirmOpening(_ path: String) -> Bool {
        guard isExecutable(path) else { return true }
        let alert = NSAlert()
        alert.messageText = "Open “\((path as NSString).lastPathComponent)”?"
        alert.informativeText = """
            This file can run programs on your Mac. Open it only if you trust the \
            person who sent it. macOS will check it before it runs.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Open")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
