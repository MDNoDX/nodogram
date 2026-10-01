//  Initial-based avatar.
//
//  Colour is derived deterministically from the identifier, so the same chat
//  always gets the same colour across launches without storing anything.

import SwiftUI

public struct Avatar: View {
    private let title: String
    private let seed: Int64
    private let size: CGFloat

    public init(title: String, seed: Int64, size: CGFloat = Theme.Metrics.avatarSize) {
        self.title = title
        self.seed = seed
        self.size = size
    }

    private static let palette: [Color] = [
        Color(red: 0.36, green: 0.40, blue: 0.78),
        Color(red: 0.20, green: 0.55, blue: 0.52),
        Color(red: 0.66, green: 0.36, blue: 0.56),
        Color(red: 0.76, green: 0.49, blue: 0.22),
        Color(red: 0.30, green: 0.48, blue: 0.70),
        Color(red: 0.52, green: 0.44, blue: 0.70),
    ]

    private var color: Color {
        let index = Int(UInt64(bitPattern: seed) % UInt64(Self.palette.count))
        return Self.palette[index]
    }

    /// Up to two initials, taken from the first two words.
    private var initials: String {
        let words = title
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    public var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(.white)
            }
            // The initials are decorative; the row's label carries the name for
            // VoiceOver, so announcing them twice would be noise.
            .accessibilityHidden(true)
    }
}
