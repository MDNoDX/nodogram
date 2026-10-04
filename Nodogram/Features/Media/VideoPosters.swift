//  Sharp poster frames for videos.
//
//  Telegram's video thumbnails are at most 320 px wide, which looks soft in a
//  420 pt bubble on a Retina screen. When the sender attached no cover, this
//  decodes a real frame from the video itself: the streaming loader fetches
//  only the header and one keyframe, at background priority, and the result
//  is cached on disk so it happens once per video.

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import NodogramDomain
import NodogramPlatform

@MainActor
final class VideoPosters {

    static let shared = VideoPosters()

    private var paths: [String: String] = [:]
    private var inFlight: [String: Task<String?, Never>] = [:]
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Posters are a nicety; never let them crowd out what the user is doing.
    private let maxConcurrent = 2

    private let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Nodogram/Posters", isDirectory: true)
    }()

    func cached(_ uniqueID: String) -> String? {
        if let path = paths[uniqueID] { return path }
        let path = file(for: uniqueID).path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        paths[uniqueID] = path
        return path
    }

    func poster(for video: VideoMedia, model: AppModel) async -> String? {
        let key = video.file.uniqueID
        guard !key.isEmpty else { return nil }
        if let path = cached(key) { return path }
        if let task = inFlight[key] { return await task.value }

        let task = Task<String?, Never> { [directory] in
            await acquire()
            defer { release() }
            let current = model.files.current(video.file.id) ?? video.file
            let destination = directory.appendingPathComponent("\(Self.safe(key)).jpg")
            let ext = (video.fileName as NSString).pathExtension
            if let local = current.localPath {
                return await Self.render(asset: AVURLAsset(url: URL(fileURLWithPath: local)),
                                         duration: video.duration, to: destination)
            }
            guard video.supportsStreaming, let source = model.byteSource else { return nil }
            let loader = StreamingAssetLoader(
                source: source, fileID: video.file.id, size: video.file.size,
                mimeType: video.mimeType.isEmpty ? "video/mp4" : video.mimeType, priority: 1)
            let asset = loader.makeAsset(fileExtension: ext.isEmpty ? "mp4" : ext)
            let result = await Self.render(asset: asset, duration: video.duration, to: destination)
            withExtendedLifetime(loader) {}
            return result
        }
        inFlight[key] = task
        let path = await task.value
        inFlight[key] = nil
        if let path { paths[key] = path }
        return path
    }

    private func acquire() async {
        if running < maxConcurrent { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }

    private func file(for key: String) -> URL {
        directory.appendingPathComponent("\(Self.safe(key)).jpg")
    }

    private static func safe(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    /// Decodes one frame a little way in — the very first frame is often black
    /// — and writes it as a JPEG.
    nonisolated private static func render(asset: AVURLAsset, duration: Int, to destination: URL) async -> String? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
        let seconds = duration > 3 ? 1.0 : 0
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        else { return nil }

        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        return CGImageDestinationFinalize(output) ? destination.path : nil
    }
}
