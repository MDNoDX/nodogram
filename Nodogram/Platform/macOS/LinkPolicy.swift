//  Which links Nodogram opens without asking.
//
//  A message can contain any URL scheme. Opening `file://` or another app's
//  custom scheme in one click lets a stranger's message trigger actions on
//  this Mac, so only well-understood schemes open directly; anything else
//  asks first.

import AppKit
import Foundation

public enum LinkPolicy {
    /// Schemes that are safe to open on a single click.
    static let directSchemes: Set<String> = ["http", "https", "mailto", "tel", "tg"]

    /// A URL with a scheme added when missing ("example.com" → https), or nil
    /// when it cannot be parsed.
    public static func safeURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://\(trimmed)")
    }

    public static func opensDirectly(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return directSchemes.contains(scheme)
    }

    /// Opens a link from a message, asking first for unusual schemes.
    @MainActor
    public static func open(_ url: URL) {
        if opensDirectly(url) {
            NSWorkspace.shared.open(url)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Open this link?"
        alert.informativeText = """
            “\(url.absoluteString)” opens another app or a file on this Mac. \
            Only continue if you trust the person who sent it.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Open")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(url)
        }
    }
}
