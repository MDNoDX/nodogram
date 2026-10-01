//  Chat avatar.
//
//  Three tiers, best available wins:
//    1. the downloaded photo
//    2. Telegram's tiny inline thumbnail, blurred — so a photo-shaped
//       placeholder appears instantly, before any download
//    3. initials on a colour derived from the id, stable across launches
//
//  Decoded images are cached, so scrolling a long list does not re-read files.

import SwiftUI
import AppKit

@MainActor
public final class AvatarImageCache {
    public static let shared = AvatarImageCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    public func image(atPath path: String) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    public func thumbnail(_ data: Data, key: Int64) -> NSImage? {
        let cacheKey = "thumb-\(key)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

public struct Avatar: View {
    private let title: String
    private let seed: Int64
    private let size: CGFloat
    private let imagePath: String?
    private let thumbnail: Data?
    private let isOnline: Bool
    private let isSavedMessages: Bool

    public init(
        title: String,
        seed: Int64,
        size: CGFloat = Theme.Metrics.avatarSize,
        imagePath: String? = nil,
        thumbnail: Data? = nil,
        isOnline: Bool = false,
        isSavedMessages: Bool = false
    ) {
        self.title = title
        self.seed = seed
        self.size = size
        self.imagePath = imagePath
        self.thumbnail = thumbnail
        self.isOnline = isOnline
        self.isSavedMessages = isSavedMessages
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(Theme.online)
                        .frame(width: size * 0.27, height: size * 0.27)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .offset(x: 1, y: 1)
                        .accessibilityLabel("Online")
                }
            }
            // The row's own label carries the name; announcing the picture
            // separately would only repeat it.
            .accessibilityHidden(!isOnline)
    }

    @ViewBuilder
    private var content: some View {
        if isSavedMessages {
            ZStack {
                LinearGradient(colors: [Theme.accent.opacity(0.95), Theme.accent.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else if let imagePath, let image = AvatarImageCache.shared.image(atPath: imagePath) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else if let thumbnail, let image = AvatarImageCache.shared.thumbnail(thumbnail, key: seed) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: size * 0.08)
        } else {
            ZStack {
                Theme.avatarGradient(for: seed)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    /// Up to two initials from the first two words; emoji-only names keep
    /// their first character rather than collapsing to "?".
    private var initials: String {
        let words = title.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}
