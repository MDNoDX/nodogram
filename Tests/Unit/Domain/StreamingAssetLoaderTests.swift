//  Proves the video streaming path end to end without Telegram: a real H.264
//  file is generated, served through StreamingAssetLoader from a source that
//  refuses to hand out bytes it has not "downloaded", and AVFoundation is made
//  to seek into the middle — the same byte-range path "skip 10 seconds" uses.

import Testing
import Foundation
@preconcurrency import AVFoundation
import CoreVideo
@testable import NodogramPlatform
import NodogramDomain

@Suite("StreamingAssetLoader", .serialized)
struct StreamingAssetLoaderTests {

    @Test("A streamed video reports its duration and decodes a frame mid-file")
    func streamsAndSeeks() async throws {
        let url = try await makeTestVideo(seconds: 4)
        let data = try Data(contentsOf: url)
        let source = FakeByteSource(data: data)

        let loader = StreamingAssetLoader(source: source, fileID: 1, size: Int64(data.count), mimeType: "video/mp4")
        let asset = loader.makeAsset(fileExtension: "mp4")

        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 4) < 0.2, "duration was \(duration)")

        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)

        // Random access into the middle of the file.
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, actual) = try await generator.image(at: CMTime(seconds: 2.5, preferredTimescale: 600))
        #expect(image.width == 160)
        #expect(abs(actual.seconds - 2.5) < 0.1)

        // Every byte served was prepared first — the loader never reads ahead
        // of what the source said was available.
        #expect(await source.violations == 0)
        #expect(await source.reads > 0)
        withExtendedLifetime(loader) {}
    }

    /// Writes a small H.264 MP4 with AVAssetWriter.
    private func makeTestVideo(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 120,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 120,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps = 10
        for frame in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 6 % 255), CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
}

/// Serves bytes only after `prepareRange` covered them, like TDLib does.
private actor FakeByteSource: MediaByteSource {
    private let data: Data
    private var prepared = IndexSet()
    private(set) var violations = 0
    private(set) var reads = 0

    init(data: Data) { self.data = data }

    func prepareRange(fileID: Int, offset: Int64, length: Int64, priority: Int) async throws {
        // Simulate network latency so requests genuinely overlap.
        try await Task.sleep(for: .milliseconds(2))
        prepared.insert(integersIn: Int(offset)..<min(data.count, Int(offset + length)))
    }

    func readRange(fileID: Int, offset: Int64, count: Int64) async throws -> Data {
        let range = Int(offset)..<min(data.count, Int(offset + count))
        reads += 1
        if !prepared.contains(integersIn: range) { violations += 1 }
        return data.subdata(in: range)
    }
}
