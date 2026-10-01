//  Round-trip test for the voice-message decoder.
//
//  No real voice file is available in the test environment, so the test makes
//  one: it encodes a tone with Apple's own Opus encoder, wraps the packets in
//  OGG pages exactly as Telegram's files are laid out, and decodes them back.

import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import NodogramPlatform

@Suite("OggOpusDecoder")
struct OggOpusDecoderTests {

    @Test("A packet spanning several 255-byte segments is reassembled")
    func multiSegmentPacket() throws {
        let packet = Data((0..<600).map { UInt8($0 % 251) })
        let ogg = OggWriter.page(packets: [packet], granule: 0, sequence: 0, headerType: 0)
        let parsed = try OggOpusDecoder.packets(from: ogg)
        #expect(parsed == [packet])
    }

    @Test("Non-OGG data is rejected, not misparsed")
    func rejectsNonOgg() {
        #expect(throws: OggOpusError.notOgg) {
            try OggOpusDecoder.packets(from: Data("RIFF....WAVEfmt fake header bytes".utf8))
        }
    }

    @Test("Encode → OGG → decode preserves the duration")
    func roundTrip() throws {
        let seconds = 1.5
        let packets = try encodeTone(seconds: seconds)
        let ogg = OggWriter.file(opusPackets: packets, channels: 1, preSkip: 312)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("voice.ogg")
        let destination = dir.appendingPathComponent("voice.caf")
        try ogg.write(to: source)

        let duration = try OggOpusDecoder.decode(fileAt: source, to: destination)

        // Opus works in 20 ms frames, so allow one frame either side.
        #expect(abs(duration - seconds) < 0.05, "decoded \(duration)s, expected \(seconds)s")

        let file = try AVAudioFile(forReading: destination)
        #expect(file.processingFormat.sampleRate == 48_000)
        #expect(file.length > 0)
    }

    /// Encodes a 440 Hz tone with Apple's Opus encoder and returns the packets.
    private func encodeTone(seconds: Double) throws -> [Data] {
        let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let opusFormat = AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatOpus, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1])!
        let converter = try #require(AVAudioConverter(from: pcmFormat, to: opusFormat))

        let frameCount = AVAudioFrameCount(48_000 * seconds)
        let pcm = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount)!
        pcm.frameLength = frameCount
        for i in 0..<Int(frameCount) {
            pcm.floatChannelData![0][i] = Float(sin(2 * .pi * 440 * Double(i) / 48_000) * 0.4)
        }

        var packets: [Data] = []
        // Supplied synchronously inside convert(); see PacketFeed in the decoder.
        let source = OneShotBuffer(pcm)
        while true {
            let out = AVAudioCompressedBuffer(format: opusFormat, packetCapacity: 64, maximumPacketSize: converter.maximumOutputPacketSize)
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, inputStatus in
                guard let buffer = source.take() else { inputStatus.pointee = .endOfStream; return nil }
                inputStatus.pointee = .haveData
                return buffer
            }
            if let descriptions = out.packetDescriptions {
                for i in 0..<Int(out.packetCount) {
                    let d = descriptions[i]
                    packets.append(Data(bytes: out.data + Int(d.mStartOffset), count: Int(d.mDataByteSize)))
                }
            }
            if status == .endOfStream || status == .error || out.packetCount == 0 { break }
        }
        #expect(!packets.isEmpty)
        return packets
    }
}

/// Hands out one buffer exactly once, inside AVAudioConverter's synchronous callback.
private final class OneShotBuffer: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? { defer { buffer = nil }; return buffer }
}

/// Minimal OGG muxer for tests. CRCs are left zero; the decoder does not check
/// them, because a corrupt voice note should play what it can, not fail outright.
enum OggWriter {
    static func page(packets: [Data], granule: UInt64, sequence: UInt32, headerType: UInt8) -> Data {
        var segments: [UInt8] = []
        var body = Data()
        for packet in packets {
            var remaining = packet.count
            while remaining >= 255 { segments.append(255); remaining -= 255 }
            segments.append(UInt8(remaining))
            body.append(packet)
        }
        var page = Data("OggS".utf8)
        page.append(0)
        page.append(headerType)
        page.append(contentsOf: withUnsafeBytes(of: granule.littleEndian, Array.init))
        page.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian, Array.init))
        page.append(contentsOf: withUnsafeBytes(of: sequence.littleEndian, Array.init))
        page.append(contentsOf: [0, 0, 0, 0])
        page.append(UInt8(segments.count))
        page.append(contentsOf: segments)
        page.append(body)
        return page
    }

    static func file(opusPackets: [Data], channels: UInt8, preSkip: UInt16) -> Data {
        var head = Data("OpusHead".utf8)
        head.append(1)
        head.append(channels)
        head.append(contentsOf: withUnsafeBytes(of: preSkip.littleEndian, Array.init))
        head.append(contentsOf: withUnsafeBytes(of: UInt32(48_000).littleEndian, Array.init))
        head.append(contentsOf: [0, 0, 0])
        let tags = Data("OpusTags".utf8) + Data([0, 0, 0, 0, 0, 0, 0, 0])

        var out = page(packets: [head], granule: 0, sequence: 0, headerType: 2)
        out.append(page(packets: [tags], granule: 0, sequence: 1, headerType: 0))
        var sequence: UInt32 = 2
        for chunk in stride(from: 0, to: opusPackets.count, by: 20) {
            let slice = Array(opusPackets[chunk..<min(chunk + 20, opusPackets.count)])
            out.append(page(packets: slice, granule: UInt64((chunk + slice.count) * 960), sequence: sequence, headerType: 0))
            sequence += 1
        }
        return out
    }
}
