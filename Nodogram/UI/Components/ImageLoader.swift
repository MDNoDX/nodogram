//  Off-main-thread image decoding with downsampling.
//
//  Decoding a 2560-pixel photo on the main thread to show it at 300 points is
//  the classic cause of stuttering chat scrolls. ImageIO decodes straight to
//  the size actually needed, on a background thread, and the result is cached.

import AppKit
import ImageIO
import SwiftUI

@MainActor
public final class ImageLoader {
    public static let shared = ImageLoader()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.totalCostLimit = 192 * 1024 * 1024
    }

    public func cached(path: String, maxPixel: Int) -> NSImage? {
        cache.object(forKey: key(path, maxPixel))
    }

    public func load(path: String, maxPixel: Int) async -> NSImage? {
        let cacheKey = key(path, maxPixel)
        if let hit = cache.object(forKey: cacheKey) { return hit }
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decode(path: path, maxPixel: maxPixel).map(UncheckedImage.init)
        }.value
        guard let cgImage = decoded?.image else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: cacheKey, cost: cgImage.width * cgImage.height * 4)
        return image
    }

    private func key(_ path: String, _ maxPixel: Int) -> NSString {
        "\(path)#\(maxPixel)" as NSString
    }

    nonisolated static func decode(path: String, maxPixel: Int) -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// `CGImage` is immutable once created, so handing it across threads is safe.
private struct UncheckedImage: @unchecked Sendable {
    let image: CGImage
}

/// An image file shown at the size needed, loaded without blocking the UI.
public struct LocalImageView<Placeholder: View>: View {
    private let path: String?
    private let maxPixel: Int
    private let contentMode: ContentMode
    private let placeholder: Placeholder

    @State private var image: NSImage?

    public init(path: String?, maxPixel: Int, contentMode: ContentMode = .fill,
                @ViewBuilder placeholder: () -> Placeholder) {
        self.path = path
        self.maxPixel = maxPixel
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: path) {
            guard let path else { image = nil; return }
            if let hit = ImageLoader.shared.cached(path: path, maxPixel: maxPixel) {
                image = hit
                return
            }
            let loaded = await ImageLoader.shared.load(path: path, maxPixel: maxPixel)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }
}

/// Telegram's tiny inline JPEG, blurred — an instant, photo-shaped placeholder.
public struct MinithumbnailView: View {
    private let data: Data?

    public init(data: Data?) {
        self.data = data
    }

    public var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 12)
                .clipped()
        } else {
            Rectangle().fill(.quaternary)
        }
    }
}
