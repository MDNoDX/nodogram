//  Inline media inside message bubbles.

import AVFoundation
import AVKit
import SwiftUI
import NodogramDomain
import NodogramPlatform
import NodogramUI

/// Fits media into the bubble while keeping its aspect ratio.
func fittedMediaSize(width: Int, height: Int, maxWidth: CGFloat = 340, maxHeight: CGFloat = 380) -> CGSize {
    guard width > 0, height > 0 else { return CGSize(width: 240, height: 180) }
    let scale = min(maxWidth / CGFloat(width), maxHeight / CGFloat(height), 1.6)
    let w = max(140, CGFloat(width) * scale)
    let h = max(90, CGFloat(height) * scale)
    return CGSize(width: min(w, maxWidth), height: min(h, maxHeight))
}

struct MessageMediaView: View {
    let message: Message
    let media: MessageMedia
    let model: AppModel

    var body: some View {
        switch media {
        case .photo(let photo):
            PhotoBubble(photo: photo, model: model) { model.openViewer(message) }
        case .video(let video):
            VideoBubble(video: video, isAnimation: false, model: model) { model.openViewer(message) }
        case .animation(let video):
            VideoBubble(video: video, isAnimation: true, model: model) { model.openViewer(message) }
        case .videoNote(let note):
            VideoNoteBubble(note: note, model: model)
        case .voiceNote(let voice):
            VoiceNoteBubble(message: message, voice: voice, model: model)
        case .audio(let audio):
            AudioFileBubble(message: message, audio: audio, model: model)
        case .document(let document):
            DocumentBubble(message: message, document: document, model: model)
        case .sticker(let sticker):
            StickerBubble(sticker: sticker, model: model)
        }
    }
}

// MARK: - Photo

private struct PhotoBubble: View {
    let photo: PhotoMedia
    let model: AppModel
    let onOpen: () -> Void

    var body: some View {
        let state = model.files.state(for: photo.preview)
        let size = fittedMediaSize(width: photo.width, height: photo.height)

        ZStack {
            MinithumbnailView(data: photo.minithumbnail)
            LocalImageView(path: state.file.localPath, maxPixel: 900) { Color.clear }
            if !state.file.isComplete {
                ProgressRing(progress: state.file.progress)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .task(id: photo.preview.id) {
            // Photos download as soon as they scroll into view, like Telegram's
            // default; they are small and expected to just be there.
            if !state.file.isComplete { _ = await model.fetch(photo.preview, priority: 4) }
        }
        .accessibilityLabel("Photo")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Video and GIF

private struct VideoBubble: View {
    let video: VideoMedia
    let isAnimation: Bool
    let model: AppModel
    let onOpen: () -> Void

    var body: some View {
        let state = model.files.state(for: video.file)
        let thumb = video.thumbnail.map { model.files.state(for: $0) }
        let size = fittedMediaSize(width: video.width, height: video.height)

        ZStack {
            MinithumbnailView(data: video.minithumbnail)
            LocalImageView(path: thumb?.file.localPath, maxPixel: 700) { Color.clear }

            if isAnimation, let path = state.file.localPath {
                // GIFs play inline, silently and on loop, once downloaded.
                LoopingVideoView(path: path)
            } else if !isAnimation {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.black.opacity(0.45), in: Circle())
            }

            if isAnimation, !state.file.isComplete {
                ProgressRing(progress: state.file.progress)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 4) {
                Text(isAnimation ? "GIF" : formatDuration(Double(video.duration)))
                if !isAnimation, state.file.isDownloading, let progress = state.file.progress {
                    Text("· \(Int(progress * 100))%")
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5), in: Capsule())
            .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .task(id: video.file.id) {
            if let thumbnail = video.thumbnail { _ = await model.fetch(thumbnail, priority: 4) }
            // Small GIFs auto-download; full videos stream on demand instead.
            if isAnimation, !state.file.isComplete, video.file.size < 8 * 1024 * 1024 {
                model.download(video.file, priority: 2)
            }
        }
        .accessibilityLabel(isAnimation ? "GIF" : "Video, \(formatDuration(Double(video.duration)))")
        .accessibilityAddTraits(.isButton)
    }
}

/// Silent, looping inline playback for GIFs.
struct LoopingVideoView: NSViewRepresentable {
    let path: String

    final class PlayerNSView: NSView {
        let playerLayer = AVPlayerLayer()
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError("unused") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func load(_ url: URL) {
            let item = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true
            looper = AVPlayerLooper(player: player, templateItem: item)
            playerLayer.player = player
            self.player = player
            player.play()
        }
    }

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.load(URL(fileURLWithPath: path))
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {}

    static func dismantleNSView(_ view: PlayerNSView, coordinator: ()) {
        view.player?.pause()
        view.looper = nil
    }
}

// MARK: - Round video message

private struct VideoNoteBubble: View {
    let note: VideoNoteMedia
    let model: AppModel

    @State private var player: AVPlayer?
    @State private var progress: Double = 0
    @State private var isPlaying = false
    @State private var wantsToPlay = false
    @State private var observer: Any?

    private let diameter: CGFloat = 220

    var body: some View {
        let state = model.files.state(for: note.file)
        let thumb = note.thumbnail.map { model.files.state(for: $0) }

        ZStack {
            MinithumbnailView(data: note.minithumbnail)
            LocalImageView(path: thumb?.file.localPath, maxPixel: 500) { Color.clear }
            if let player {
                PlayerLayerView(player: player)
            }
            if !isPlaying {
                if wantsToPlay && !state.file.isComplete {
                    ProgressRing(progress: state.file.progress)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
                .opacity(player == nil ? 0 : 1)
        }
        .overlay(alignment: .bottom) {
            Text(formatDuration(player == nil ? Double(note.duration) : progress * Double(note.duration)))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(.bottom, 10)
        }
        .contentShape(Circle())
        .onTapGesture { toggle(state: state) }
        .task(id: note.file.id) {
            if let thumbnail = note.thumbnail { _ = await model.fetch(thumbnail, priority: 4) }
        }
        .onChange(of: state.file.isComplete) { _, complete in
            if complete, wantsToPlay, player == nil, let path = state.file.localPath { start(path) }
        }
        .onDisappear { stop() }
        .accessibilityLabel("Video message, \(formatDuration(Double(note.duration)))")
        .accessibilityAddTraits(.isButton)
    }

    private func toggle(state: FileState) {
        if let player {
            if isPlaying { player.pause() } else { AudioPlayback.shared.pause(); player.play() }
            isPlaying.toggle()
            return
        }
        wantsToPlay = true
        if let path = state.file.localPath {
            start(path)
        } else {
            model.download(note.file, priority: 32)
        }
    }

    private func start(_ path: String) {
        AudioPlayback.shared.pause()
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { time in
            MainActor.assumeIsolated {
                let total = Double(note.duration)
                progress = total > 0 ? min(1, time.seconds / total) : 0
                if progress >= 0.999 { isPlaying = false }
            }
        }
        self.player = player
        isPlaying = true
        player.play()
    }

    private func stop() {
        if let observer { player?.removeTimeObserver(observer) }
        player?.pause()
        player = nil
        observer = nil
        isPlaying = false
        progress = 0
    }
}

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view.layer?.sublayers?.first as? AVPlayerLayer)?.frame = view.bounds
    }
}

// MARK: - Voice message

private struct VoiceNoteBubble: View {
    let message: Message
    let voice: VoiceNoteMedia
    let model: AppModel

    var body: some View {
        let playback = AudioPlayback.shared
        let isCurrent = playback.isCurrent(message.id)

        HStack(spacing: 10) {
            PlayButton(
                isPlaying: isCurrent && playback.isPlaying,
                isLoading: isCurrent && playback.isPreparing
            ) {
                playback.toggle(message, file: voice.file) { await model.fetch($0, priority: 32) }
            }

            VStack(alignment: .leading, spacing: 4) {
                WaveformView(
                    samples: voice.waveform,
                    progress: isCurrent ? playback.progress : 0,
                    outgoing: message.isOutgoing
                ) { fraction in
                    if isCurrent { playback.seek(to: fraction) }
                }
                .frame(height: 26)

                HStack(spacing: 6) {
                    Text(isCurrent && playback.position > 0
                         ? formatDuration(playback.position)
                         : formatDuration(Double(voice.duration)))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)

                    if isCurrent && (playback.isPlaying || playback.position > 0) {
                        Button {
                            playback.cycleRate()
                        } label: {
                            Text(rateLabel(playback.rate))
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accent.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Playback speed")
                    }

                    if isCurrent, let failure = playback.failure {
                        Text(failure).font(.system(size: 11)).foregroundStyle(Theme.failure)
                    }
                }
            }
            .frame(width: 210)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice message, \(formatDuration(Double(voice.duration)))")
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1 ? "1×" : (rate == 2 ? "2×" : "1.5×")
    }
}

struct PlayButton: View {
    let isPlaying: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.accent)
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 1.5)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// Telegram's waveform, resampled to a fixed number of bars. Click or drag to
/// seek while playing.
struct WaveformView: View {
    let samples: [UInt8]
    let progress: Double
    let outgoing: Bool
    let onSeek: (Double) -> Void

    private let barCount = 46

    var body: some View {
        GeometryReader { geometry in
            let bars = resampled()
            let spacing: CGFloat = 1.6
            let width = max(1.2, (geometry.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(bars.indices, id: \.self) { index in
                    let played = Double(index) / Double(barCount) < progress
                    Capsule()
                        .fill(played ? Theme.accent : Color.secondary.opacity(0.4))
                        .frame(width: width, height: max(3, geometry.size.height * bars[index]))
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                onSeek(max(0, min(1, value.location.x / geometry.size.width)))
            })
        }
    }

    private func resampled() -> [CGFloat] {
        guard !samples.isEmpty else { return Array(repeating: 0.25, count: barCount) }
        let peak = max(1, CGFloat(samples.max() ?? 31))
        return (0..<barCount).map { index in
            let start = index * samples.count / barCount
            let end = max(start + 1, (index + 1) * samples.count / barCount)
            let slice = samples[start..<min(end, samples.count)]
            let value = CGFloat(slice.max() ?? 0) / peak
            return 0.15 + 0.85 * value
        }
    }
}

// MARK: - Audio file

private struct AudioFileBubble: View {
    let message: Message
    let audio: AudioMedia
    let model: AppModel

    var body: some View {
        let playback = AudioPlayback.shared
        let isCurrent = playback.isCurrent(message.id)

        HStack(spacing: 10) {
            PlayButton(isPlaying: isCurrent && playback.isPlaying, isLoading: isCurrent && playback.isPreparing) {
                playback.toggle(message, file: audio.file) { await model.fetch($0, priority: 32) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(audio.title.isEmpty ? (audio.fileName.isEmpty ? "Audio" : audio.fileName) : audio.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if isCurrent {
                    ProgressView(value: playback.progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .frame(width: 180)
                }
                Text([audio.performer,
                      isCurrent ? "\(formatDuration(playback.position)) / \(formatDuration(playback.duration))"
                                : formatDuration(Double(audio.duration))]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 160, alignment: .leading)
        }
    }
}

// MARK: - Document

private struct DocumentBubble: View {
    let message: Message
    let document: DocumentMedia
    let model: AppModel

    var body: some View {
        let state = model.files.state(for: document.file)
        let file = state.file

        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Theme.accent.opacity(0.85))
                if file.isDownloading {
                    ProgressRing(progress: file.progress, tint: .white, size: 30)
                } else if file.isComplete {
                    Text(fileExtension)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 3)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.fileName.isEmpty ? "File" : document.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(status(file))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, maxWidth: 260, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { tap(file) }
        .onChange(of: file.isComplete) { _, complete in
            if complete, MediaLibrary.autoSave, message.canBeSaved, let path = file.localPath {
                _ = try? MediaLibrary.save(localPath: path, suggestedName: message.media?.suggestedFileName ?? "File",
                                           uniqueID: file.uniqueID)
            }
        }
        .accessibilityLabel("File \(document.fileName), \(file.sizeDescription)")
        .accessibilityAddTraits(.isButton)
    }

    private var fileExtension: String {
        let ext = (document.fileName as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : String(ext.prefix(4))
    }

    private func status(_ file: MediaFile) -> String {
        if file.isDownloading, file.size > 0 {
            let done = ByteCountFormatter.string(fromByteCount: file.downloadedSize, countStyle: .file)
            return "\(done) of \(file.sizeDescription)"
        }
        if file.isComplete { return message.canBeSaved ? "\(file.sizeDescription) · Click to open" : file.sizeDescription }
        return file.sizeDescription
    }

    private func tap(_ file: MediaFile) {
        if file.isComplete {
            MediaActions.openDocument(message, file: file, model: model)
        } else if file.isDownloading {
            model.cancelDownload(file)
        } else {
            model.download(file, priority: 16)
        }
    }
}

// MARK: - Sticker

private struct StickerBubble: View {
    let sticker: StickerMedia
    let model: AppModel

    var body: some View {
        // Animated (TGS) and video (WebM) stickers cannot be drawn natively,
        // so they show their still thumbnail; static WebP stickers show fully.
        let shown = sticker.format == .still ? sticker.file : sticker.thumbnail
        let state = shown.map { model.files.state(for: $0) }
        let size = fittedMediaSize(width: sticker.width, height: sticker.height, maxWidth: 170, maxHeight: 170)

        ZStack {
            if let path = state?.file.localPath {
                LocalImageView(path: path, maxPixel: 340, contentMode: .fit) { Color.clear }
            } else {
                Text(sticker.emoji.isEmpty ? "🙂" : sticker.emoji)
                    .font(.system(size: 64))
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: shown?.id) {
            if let shown { _ = await model.fetch(shown, priority: 4) }
        }
        .accessibilityLabel("Sticker \(sticker.emoji)")
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double?
    var tint: Color = .white
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(tint == .white ? 0.4 : 0))
            Circle().stroke(tint.opacity(0.3), lineWidth: 3).padding(5)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.03, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                    .animation(.linear(duration: 0.2), value: progress)
            } else {
                ProgressView().controlSize(.small).tint(tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(progress.map { "Downloading, \(Int($0 * 100)) percent" } ?? "Loading")
    }
}
