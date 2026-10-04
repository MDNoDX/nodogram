//  Prepares files the user drops, picks or attaches for sending.
//
//  Decides photo / video / document by content type, reads dimensions so
//  Telegram lays the media out correctly, and converts photos Telegram cannot
//  take as-is (HEIC, TIFF…) to JPEG.

import AVFoundation
import Foundation
import ImageIO
import NodogramDomain
import UniformTypeIdentifiers

public enum OutgoingFiles {

    /// Telegram's photo limit; larger images are sent as files instead.
    static let maxPhotoBytes = 10 * 1024 * 1024

    public static func prepare(_ url: URL) async -> OutgoingFile {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if let type, type.conforms(to: .image), size <= maxPhotoBytes, type != .gif, type != .svg {
            let (width, height) = imageSize(url)
            if type == .jpeg || type == .png || type == .webP {
                return OutgoingFile(path: url.path, kind: .photo, width: width, height: height)
            }
            if let converted = convertToJPEG(url) {
                return OutgoingFile(path: converted.path, kind: .photo, width: width, height: height)
            }
        }

        if let type, type.conforms(to: .movie) {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            var width = 0, height = 0
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                width = Int(abs(rect.width)); height = Int(abs(rect.height))
            }
            return OutgoingFile(path: url.path, kind: .video, width: width, height: height,
                                duration: duration.isFinite ? Int(duration.rounded()) : 0)
        }

        return OutgoingFile(path: url.path, kind: .document)
    }

    private static func imageSize(_ url: URL) -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (0, 0) }
        var width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        // EXIF orientations 5–8 rotate by 90°.
        if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation >= 5 { swap(&width, &height) }
        return (width, height)
    }

    private static func convertToJPEG(_ url: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
              ] as CFDictionary) else { return nil }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        guard let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(writer) ? destination : nil
    }
}
