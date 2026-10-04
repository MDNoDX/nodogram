//  Renders an emoji to an image.
//
//  macOS menu palettes display images, not text, so reaction emoji are drawn
//  once into small images (cached) for the right-click reaction row.

import AppKit
import SwiftUI

@MainActor
public enum EmojiImage {
    private static var cache: [String: NSImage] = [:]

    public static func image(_ emoji: String, size: CGFloat = 22) -> NSImage {
        let key = "\(emoji)#\(size)"
        if let hit = cache[key] { return hit }
        let font = NSFont.systemFont(ofSize: size * 0.82)
        let attributed = NSAttributedString(string: emoji, attributes: [.font: font])
        let bounds = attributed.size()
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            attributed.draw(at: NSPoint(x: (rect.width - bounds.width) / 2, y: (rect.height - bounds.height) / 2))
            return true
        }
        cache[key] = image
        return image
    }
}
