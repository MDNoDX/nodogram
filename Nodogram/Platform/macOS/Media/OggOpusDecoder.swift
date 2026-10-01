//  Decodes Telegram voice messages (Opus in an OGG container) to PCM.
//
//  AVFoundation cannot open OGG files, but macOS ships a native Opus decoder
//  (verified: AVAudioConverter accepts kAudioFormatOpus). So this demuxes the
//  OGG pages into Opus packets and hands those to the system decoder — no
//  third-party codec, no bundled C library.
//
//  Voice messages are short, so the whole file is decoded once to a PCM CAF in
//  the cache. AVAudioPlayer then gives seeking and variable speed for free.

import AVFoundation
import Foundation

public enum OggOpusError: Error, Equatable {
    case notOgg
    case missingOpusHead
    case unsupportedChannelCount(Int)
    case decoderUnavailable
    case decodingFailed(String)
}

public enum OggOpusDecoder {

    /// Opus always decodes at 48 kHz, whatever the original input rate was.
    static let sampleRate: Double = 48_000

    // MARK: - Demuxing

    /// Splits an OGG stream into its logical packets.
    ///
    /// A packet is a run of segments; a segment shorter than 255 bytes ends it.
    /// Packets may continue across page boundaries, which is why the partial
    /// packet carries over between pages.
    static func packets(from data: Data) throws -> [Data] {
        let bytes = [UInt8](data)
        var packets: [Data] = []
        var partial = [UInt8]()
        var position = 0

        while position + 27 <= bytes.count {
            guard bytes[position] == 0x4F, bytes[position + 1] == 0x67,
                  bytes[position + 2] == 0x67, bytes[position + 3] == 0x53 else {
                // "OggS" missing: only fatal before any page has been read.
                if packets.isEmpty && partial.isEmpty { throw OggOpusError.notOgg }
                break
            }
            let segmentCount = Int(bytes[position + 26])
            let tableStart = position + 27
            guard tableStart + segmentCount <= bytes.count else { break }

            var dataPosition = tableStart + segmentCount
            for index in 0..<segmentCount {
                let length = Int(bytes[tableStart + index])
                guard dataPosition + length <= bytes.count else { break }
                partial.append(contentsOf: bytes[dataPosition..<dataPosition + length])
                dataPosition += length
                if length < 255 {
                    packets.append(Data(partial))
                    partial.removeAll(keepingCapacity: true)
                }
            }
            position = dataPosition
        }
        return packets
    }

    struct Header: Equatable {
        let channels: Int
        let preSkip: Int
    }

    static func header(from packet: Data) throws -> Header {
        let bytes = [UInt8](packet)
        guard bytes.count >= 19, String(bytes: bytes[0..<8], encoding: .ascii) == "OpusHead" else {
            throw OggOpusError.missingOpusHead
        }
        let channels = Int(bytes[9])
        guard channels == 1 || channels == 2 else { throw OggOpusError.unsupportedChannelCount(channels) }
        let preSkip = Int(bytes[10]) | Int(bytes[11]) << 8
        return Header(channels: channels, preSkip: preSkip)
    }

    // MARK: - Decoding

    /// Decodes an OGG Opus file to a 48 kHz PCM CAF at `destination`.
    /// - Returns: The duration in seconds.
    @discardableResult
    public static func decode(fileAt source: URL, to destination: URL) throws -> TimeInterval {
        let packets = try packets(from: try Data(contentsOf: source, options: .mappedIfSafe))
        guard let first = packets.first else { throw OggOpusError.missingOpusHead }
        let header = try header(from: first)

        // Packet 0 is OpusHead, packet 1 OpusTags; audio starts at 2.
        let audioPackets = packets.dropFirst(2).filter { !$0.isEmpty }

        guard
            let inputFormat = AVAudioFormat(settings: [
                AVFormatIDKey: kAudioFormatOpus,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: header.channels,
            ]),
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                channels: AVAudioChannelCount(header.channels), interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else { throw OggOpusError.decoderUnavailable }

        let output = try AVAudioFile(forWriting: destination, settings: outputFormat.settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)

        let feed = PacketFeed(packets: Array(audioPackets))
        var samplesToSkip = header.preSkip
        var totalFrames: AVAudioFramePosition = 0

        while !feed.finished {
            // 120 ms is the longest Opus frame; a few of them per pass.
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 5_760 * 4) else {
                throw OggOpusError.decodingFailed("Could not allocate an output buffer")
            }

            var conversionError: NSError?
            let status = converter.convert(to: buffer, error: &conversionError) { _, inputStatus in
                guard let packet = feed.next() else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                let compressed = AVAudioCompressedBuffer(
                    format: inputFormat, packetCapacity: 1, maximumPacketSize: packet.count)
                packet.withUnsafeBytes { raw in
                    compressed.data.copyMemory(from: raw.baseAddress!, byteCount: packet.count)
                }
                compressed.byteLength = UInt32(packet.count)
                compressed.packetCount = 1
                compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(
                    mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
                inputStatus.pointee = .haveData
                return compressed
            }

            if status == .error {
                throw OggOpusError.decodingFailed(conversionError?.localizedDescription ?? "unknown")
            }

            // Opus streams begin with encoder priming samples ("pre-skip") that
            // are not part of the audio and would otherwise be an audible click.
            var frames = Int(buffer.frameLength)
            if samplesToSkip > 0, frames > 0 {
                let skip = min(samplesToSkip, frames)
                samplesToSkip -= skip
                frames -= skip
                if frames > 0, let channels = buffer.floatChannelData {
                    for channel in 0..<Int(outputFormat.channelCount) {
                        let pointer = channels[channel]
                        pointer.update(from: pointer + skip, count: frames)
                    }
                }
                buffer.frameLength = AVAudioFrameCount(frames)
            }

            if buffer.frameLength > 0 {
                try output.write(from: buffer)
                totalFrames += AVAudioFramePosition(buffer.frameLength)
            }
            if status == .endOfStream { feed.finished = true }
        }

        return Double(totalFrames) / sampleRate
    }
}

/// Packets handed to AVAudioConverter one at a time.
///
/// The converter's input block is declared `@Sendable`, but `convert(to:error:
/// withInputFrom:)` invokes it synchronously on the calling thread before
/// returning — the state is never touched concurrently. This box states that
/// explicitly instead of silencing the checker.
private final class PacketFeed: @unchecked Sendable {
    private var remaining: ArraySlice<Data>
    var finished = false

    init(packets: [Data]) {
        remaining = packets[...]
    }

    func next() -> Data? {
        guard let packet = remaining.popFirst() else {
            finished = true
            return nil
        }
        return packet
    }
}
