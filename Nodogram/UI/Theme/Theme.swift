//  Nodogram's visual tokens.
//
//  Original brand identity — deliberately NOT Telegram's palette.
//  Telegram's accent is #2AABEE / #229ED9; Nodogram's is a slate-indigo chosen
//  to be clearly distinct. See Documentation/LEGAL_AND_LICENSES.md §5.
//
//  Colours are defined once here so the app stays coherent and so honouring the
//  system accent colour is a single switch rather than a sweep.

import SwiftUI

public enum Theme {
    /// Nodogram's own accent.
    public static let accent = Color(red: 0.36, green: 0.40, blue: 0.78)

    /// A muted companion used for secondary emphasis.
    public static let accentSoft = Color(red: 0.36, green: 0.40, blue: 0.78).opacity(0.14)

    // Semantic colours, mapped to AppKit's dynamic system colours so light and
    // dark mode, increased contrast, and reduced transparency all work without
    // per-mode branching.
    public static let primaryText = Color(nsColor: .labelColor)
    public static let secondaryText = Color(nsColor: .secondaryLabelColor)
    public static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    public static let separator = Color(nsColor: .separatorColor)
    public static let listBackground = Color(nsColor: .controlBackgroundColor)
    public static let contentBackground = Color(nsColor: .textBackgroundColor)
    public static let selection = Color(nsColor: .selectedContentBackgroundColor)

    /// Status colours. Never the *only* signal — every state also carries an
    /// icon or text, per the accessibility rule that colour alone must not
    /// communicate state (brief §54).
    public static let success = Color(nsColor: .systemGreen)
    public static let warning = Color(nsColor: .systemOrange)
    public static let failure = Color(nsColor: .systemRed)

    /// Presence indicator. Paired with the word "online" in headers, so colour
    /// is never the only signal.
    public static let online = Color(nsColor: .systemGreen)

    /// Bubble fills. Incoming uses a neutral system fill so it adapts to light,
    /// dark and increased-contrast modes; outgoing carries the brand accent.
    public static let bubbleIncoming = Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.55)
    public static let bubbleOutgoing = accent.opacity(0.17)

    private static let avatarPalette: [(Color, Color)] = [
        (Color(red: 0.42, green: 0.47, blue: 0.86), Color(red: 0.32, green: 0.36, blue: 0.74)),
        (Color(red: 0.25, green: 0.66, blue: 0.62), Color(red: 0.16, green: 0.52, blue: 0.50)),
        (Color(red: 0.78, green: 0.42, blue: 0.64), Color(red: 0.64, green: 0.30, blue: 0.52)),
        (Color(red: 0.90, green: 0.60, blue: 0.30), Color(red: 0.78, green: 0.46, blue: 0.20)),
        (Color(red: 0.36, green: 0.58, blue: 0.84), Color(red: 0.24, green: 0.44, blue: 0.72)),
        (Color(red: 0.60, green: 0.50, blue: 0.84), Color(red: 0.47, green: 0.38, blue: 0.72)),
        (Color(red: 0.86, green: 0.44, blue: 0.40), Color(red: 0.72, green: 0.32, blue: 0.30)),
    ]

    /// Deterministic per id, so a chat keeps its colour across launches.
    public static func avatarGradient(for seed: Int64) -> LinearGradient {
        let pair = avatarPalette[Int(UInt64(bitPattern: seed) % UInt64(avatarPalette.count))]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .top, endPoint: .bottom)
    }

    /// Sender-name colour in group chats, from the same palette, so a person's
    /// name and initials avatar match.
    public static func senderColor(for seed: Int64) -> Color {
        avatarPalette[Int(UInt64(bitPattern: seed) % UInt64(avatarPalette.count))].1
    }

    public enum Metrics {
        public static let sidebarMinWidth: CGFloat = 196
        public static let sidebarIdealWidth: CGFloat = 220
        public static let chatListMinWidth: CGFloat = 260
        public static let chatListIdealWidth: CGFloat = 320
        public static let conversationMinWidth: CGFloat = 420

        public static let rowVerticalPadding: CGFloat = 7
        public static let rowHorizontalPadding: CGFloat = 10
        public static let avatarSize: CGFloat = 44
        public static let cornerRadius: CGFloat = 7
    }

    public enum Typography {
        public static let chatTitle = Font.system(size: 13, weight: .semibold)
        public static let chatPreview = Font.system(size: 12, weight: .regular)
        public static let timestamp = Font.system(size: 11, weight: .regular)
        public static let sectionHeader = Font.system(size: 11, weight: .semibold)
        public static let messageBody = Font.system(size: 13, weight: .regular)
        public static let code = Font.system(size: 12, design: .monospaced)
    }
}
