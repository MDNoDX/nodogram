//  Voice-message and audio-file playback.
//
//  One shared player: starting a voice message stops any other, as in every
//  messenger. Voice messages (OGG Opus) are decoded once to PCM in the cache by
//  OggOpusDecoder; ordinary audio files play directly.
//
//  When a voice message ends, the next one in the conversation starts — how
//  people listen to a run of voice replies.

import AVFoundation
import Foundation
import Observation
import OSLog
import NodogramDomain
import NodogramPlatform

private let log = Logger(subsystem: "app.nodogram", category: "audio")

@MainActor
@Observable
public final class AudioPlayback: NSObject {
    public static let shared = AudioPlayback()

    public private(set) var currentID: MessageID?
    public private(set) var isPlaying = false
    public private(set) var isPreparing = false
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var failure: String?

    /// Persisted, so a preferred speed sticks across launches.
    public private(set) var rate: Float = {
        let stored = UserDefaults.standard.float(forKey: "playback.voiceRate")
        return stored > 0 ? stored : 1
    }()

    /// Called when playback of `currentID` ends naturally, to start the next.
    public var onFinished: ((MessageID) -> Void)?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?

    public var progress: Double {
        duration > 0 ? min(1, position / duration) : 0
    }

    public func isCurrent(_ id: MessageID) -> Bool { currentID == id }

    /// Plays, pauses or resumes the given message's audio.
    public func toggle(_ message: Message, file: MediaFile, fetch: @escaping (MediaFile) async -> MediaFile?) {
        if currentID == message.id, let player {
            if player.isPlaying { pause() } else { resume() }
            return
        }
        start(message, file: file, fetch: fetch)
    }

    public func start(_ message: Message, file: MediaFile, fetch: @escaping (MediaFile) async -> MediaFile?) {
        stop()
        currentID = message.id
        isPreparing = true
        failure = nil

        let isOggOpus: Bool = {
            if case .voiceNote = message.media { return true }
            return false
        }()

        Task {
            guard let local = await fetch(file), let path = local.localPath else {
                self.fail("Couldn't download this audio.", for: message.id)
                return
            }
            do {
                let url = isOggOpus
                    ? try await Self.decodedVoiceURL(source: path, uniqueID: file.uniqueID)
                    : URL(fileURLWithPath: path)
                guard self.currentID == message.id else { return }   // user moved on meanwhile
                let player = try AVAudioPlayer(contentsOf: url)
                player.enableRate = true
                player.rate = self.rate
                player.delegate = self
                player.prepareToPlay()
                self.player = player
                self.duration = player.duration
                self.isPreparing = false
                self.resume()
            } catch {
                log.error("audio failed: \(String(describing: error), privacy: .public)")
                self.fail("This audio couldn't be played.", for: message.id)
            }
        }
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        ticker?.invalidate()
    }

    public func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTicker()
    }

    public func stop() {
        player?.stop()
        player = nil
        ticker?.invalidate()
        isPlaying = false
        isPreparing = false
        position = 0
        duration = 0
        currentID = nil
    }

    /// Seeks within the current message, `fraction` 0…1.
    public func seek(to fraction: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(1, fraction)) * player.duration
        position = player.currentTime
    }

    public func skip(by seconds: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(player.duration, player.currentTime + seconds))
        position = player.currentTime
    }

    /// 1× → 1.5× → 2× → 1×.
    public func cycleRate() {
        rate = rate < 1.25 ? 1.5 : (rate < 1.75 ? 2 : 1)
        player?.rate = rate
        UserDefaults.standard.set(rate, forKey: "playback.voiceRate")
    }

    private func startTicker() {
        ticker?.invalidate()
        // 20 Hz is smooth for a progress bar without measurable cost.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
            }
        }
    }

    private func fail(_ message: String, for id: MessageID) {
        guard currentID == id else { return }
        failure = message
        isPreparing = false
        isPlaying = false
    }

    /// Decodes a voice message to PCM once and reuses the result.
    private static func decodedVoiceURL(source: String, uniqueID: String) async throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nodogram/voice", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(uniqueID.isEmpty ? UUID().uuidString : uniqueID).caf")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        let input = URL(fileURLWithPath: source)
        // Decoding is CPU work: never on the main thread.
        try await Task.detached(priority: .userInitiated) {
            let partial = destination.appendingPathExtension("partial")
            try? FileManager.default.removeItem(at: partial)
            try OggOpusDecoder.decode(fileAt: input, to: partial)
            try FileManager.default.moveItem(at: partial, to: destination)
        }.value
        return destination
    }
}

extension AudioPlayback: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        MainActor.assumeIsolated {
            guard let finished = currentID else { return }
            ticker?.invalidate()
            isPlaying = false
            position = 0
            onFinished?(finished)
        }
    }
}
