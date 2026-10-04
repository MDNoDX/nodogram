//  Full-window media viewer, in the style of Telegram's: the conversation dims
//  away and the photo or video takes the window.
//
//  Keyboard:
//    Photos   ← →  previous / next      + −  zoom      R  rotate
//    Videos   ← →  back / forward 10 s   space  play/pause   J K L  too
//             ⌥← ⌥→  previous / next item
//    Both     esc  close                 ⌘S  save        ⌘⇧R  show in Finder

import AppKit
import AVFoundation
import AVKit
import SwiftUI
import NodogramDomain
import NodogramPlatform
import NodogramUI

struct MediaViewerOverlay: View {
    let model: AppModel

    @State private var keyMonitor: Any?
    @State private var video = VideoPlaybackController()
    @State private var photoZoom = PhotoZoomCommands()

    var body: some View {
        if let id = model.viewerMessageID,
           let message = model.messages.first(where: { $0.id == id }),
           let media = message.media {
            ZStack {
                // Opaque: nothing of the chat shows through behind the photo.
                Color.black
                    .ignoresSafeArea()

                content(message: message, media: media)
                    .padding(.top, 54)
                    .padding(.bottom, isVideo(media) ? 70 : (model.viewableMedia.count > 1 ? 96 : 54))
                    .padding(.horizontal, 64)

                chrome(message: message, media: media)
            }
            .transition(.opacity)
            .onAppear(perform: installKeys)
            .onDisappear(perform: removeKeys)
            .onChange(of: id) { _, _ in video.teardown() }
        }
    }

    @ViewBuilder
    private func content(message: Message, media: MessageMedia) -> some View {
        switch media {
        case .photo(let photo):
            PhotoViewer(photo: photo, model: model, commands: photoZoom)
                .id(message.id)
        case .video(let v), .animation(let v):
            VideoViewer(message: message, video: v, model: model, controller: video)
                .id(message.id)
        default:
            EmptyView()
        }
    }

    private func isVideo(_ media: MessageMedia) -> Bool {
        switch media {
        case .video, .animation: return true
        default: return false
        }
    }

    // MARK: Chrome

    private func chrome(message: Message, media: MessageMedia) -> some View {
        let items = model.viewableMedia
        let index = items.firstIndex { $0.id == message.id }

        return VStack {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.isOutgoing ? "You" : (message.senderName.isEmpty ? (model.selectedChat?.title ?? "") : message.senderName))
                        .font(.system(size: 13, weight: .semibold))
                    Text(message.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if let index {
                    Text("\(index + 1) of \(items.count)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()

                if case .photo = media {
                    ViewerButton(symbol: "minus.magnifyingglass", help: "Zoom out (−)") { photoZoom.zoom(by: 1 / 1.5) }
                    ViewerButton(symbol: "plus.magnifyingglass", help: "Zoom in (+)") { photoZoom.zoom(by: 1.5) }
                    ViewerButton(symbol: "rotate.right", help: "Rotate (R)") { photoZoom.rotate() }
                }
                if message.canBeSaved {
                    ViewerButton(symbol: "square.and.arrow.down", help: "Save to Downloads (⌘S)") {
                        MediaActions.save(message, model: model, reveal: false)
                    }
                    ViewerButton(symbol: "folder", help: "Show in Finder (⌘⇧R)") {
                        MediaActions.save(message, model: model, reveal: true)
                    }
                } else {
                    Label("Saving off", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .help("This chat doesn't allow saving its media.")
                }
                ViewerButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Full Screen (F)") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                ViewerButton(symbol: "bubble.left", help: "Show in Chat") {
                    let id = message.id
                    close()
                    model.jump(to: id)
                }
                ViewerButton(symbol: "xmark", help: "Close (esc)") { close() }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.35))

            Spacer()
        }
        .overlay(alignment: .leading) {
            if let index, index > 0 {
                NavArrow(symbol: "chevron.left") { go(to: items[index - 1]) }
            }
        }
        .overlay(alignment: .trailing) {
            if let index, index + 1 < items.count {
                NavArrow(symbol: "chevron.right") { go(to: items[index + 1]) }
            }
        }
        .overlay(alignment: .bottom) {
            if !isVideo(media) {
                VStack(spacing: 8) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                            .frame(maxWidth: 640)
                            .textSelection(.enabled)
                    }
                    if items.count > 1 {
                        Filmstrip(items: items, currentID: message.id, model: model) { go(to: $0) }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.bottom, isVideo(media) ? 92 : 24)
                    .transition(.opacity)
            }
        }
    }

    private func go(to message: Message) {
        video.teardown()
        model.openViewer(message)
    }

    private func close() {
        video.teardown()
        withAnimation(.easeOut(duration: 0.15)) { model.closeViewer() }
    }

    private func step(_ delta: Int) {
        let items = model.viewableMedia
        guard let id = model.viewerMessageID, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard items.indices.contains(target) else { return }
        go(to: items[target])
    }

    // MARK: Keyboard

    /// A local monitor sees keys before AVPlayerView does, so arrows always mean
    /// "10 seconds" here instead of the player's frame-stepping.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Local monitors run on the main thread. Only plain values cross
            // into the main-actor handler; the event itself is not Sendable.
            let press = KeyPress(
                keyCode: event.keyCode,
                flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                key: event.charactersIgnoringModifiers?.lowercased() ?? "")
            let handled = MainActor.assumeIsolated { handle(press) }
            return handled ? nil : event
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ press: KeyPress) -> Bool {
        guard let id = model.viewerMessageID,
              let message = model.messages.first(where: { $0.id == id }),
              let media = message.media else { return false }
        let flags = press.flags
        let isVideo = self.isVideo(media)
        let key = press.key

        switch press.keyCode {
        case 53: close(); return true                                         // esc
        case 123 where flags.contains(.option) || !isVideo: step(-1); return true   // ←
        case 124 where flags.contains(.option) || !isVideo: step(1); return true    // →
        case 123: video.skip(-10); return true
        case 124: video.skip(10); return true
        case 49 where isVideo: video.togglePlay(); return true               // space
        case 3 where flags.intersection([.command, .option, .control]).isEmpty:  // F
            NSApp.keyWindow?.toggleFullScreen(nil); return true
        default: break
        }

        if flags.contains(.command) {
            if key == "s", flags.contains(.shift) == false { MediaActions.save(message, model: model, reveal: false); return true }
            if key == "r", flags.contains(.shift) { MediaActions.save(message, model: model, reveal: true); return true }
            return false
        }

        if isVideo {
            switch key {
            case "j": video.skip(-10); return true
            case "l": video.skip(10); return true
            case "k": video.togglePlay(); return true
            default: return false
            }
        }
        switch key {
        case "+", "=": photoZoom.zoom(by: 1.5); return true
        case "-": photoZoom.zoom(by: 1 / 1.5); return true
        case "0": photoZoom.reset(); return true
        case "r": photoZoom.rotate(); return true
        default: return false
        }
    }
}

private struct KeyPress: Sendable {
    let keyCode: UInt16
    let flags: NSEvent.ModifierFlags
    let key: String
}

/// Thumbnails of every photo and video in the chat, for jumping between them.
private struct Filmstrip: View {
    let items: [Message]
    let currentID: MessageID
    let model: AppModel
    let onSelect: (Message) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items, id: \.id) { item in
                        thumb(item)
                            .frame(width: item.id == currentID ? 54 : 40, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white, lineWidth: item.id == currentID ? 2 : 0))
                            .opacity(item.id == currentID ? 1 : 0.6)
                            .id(item.id)
                            .onTapGesture { onSelect(item) }
                    }
                }
                .padding(.horizontal, 12)
                .animation(.easeOut(duration: 0.15), value: currentID)
            }
            .frame(maxWidth: 720)
            .frame(height: 58)
            .onAppear { proxy.scrollTo(currentID, anchor: .center) }
            .onChange(of: currentID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
        }
    }

    @ViewBuilder
    private func thumb(_ item: Message) -> some View {
        switch item.media {
        case .photo(let photo):
            ZStack {
                MinithumbnailView(data: photo.minithumbnail)
                LocalImageView(path: model.files.state(for: photo.preview).file.localPath, maxPixel: 160) { Color.clear }
            }
        case .video(let video), .animation(let video):
            ZStack {
                MinithumbnailView(data: video.minithumbnail)
                LocalImageView(path: video.thumbnail.flatMap { model.files.state(for: $0).file.localPath }, maxPixel: 160) { Color.clear }
                Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(.white)
            }
        default:
            Color.gray.opacity(0.3)
        }
    }
}

private struct ViewerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct NavArrow: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 52, height: 90)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

// MARK: - Photo

/// Commands from the toolbar and keyboard into the AppKit zoom view.
@MainActor
final class PhotoZoomCommands {
    weak var scrollView: NSScrollView?
    var onRotate: (() -> Void)?

    func zoom(by factor: CGFloat) {
        guard let scrollView else { return }
        let target = min(scrollView.maxMagnification, max(scrollView.minMagnification, scrollView.magnification * factor))
        let center = NSPoint(x: scrollView.documentVisibleRect.midX, y: scrollView.documentVisibleRect.midY)
        scrollView.animator().setMagnification(target, centeredAt: center)
    }

    func reset() {
        scrollView?.magnification = 1
        scrollView?.needsLayout = true
    }

    func rotate() { onRotate?() }
}

private struct PhotoViewer: View {
    let photo: PhotoMedia
    let model: AppModel
    let commands: PhotoZoomCommands

    @State private var image: NSImage?
    @State private var quarterTurns = 0

    var body: some View {
        let full = model.files.state(for: photo.full)
        let preview = model.files.state(for: photo.preview)

        ZStack {
            if let image {
                ZoomableImageView(image: rotated(image), commands: commands)
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
            if !full.file.isComplete, full.file.isDownloading {
                VStack { Spacer(); ProgressRing(progress: full.file.progress).padding(.bottom, 8) }
            }
        }
        .task(id: photo.full.id) {
            commands.onRotate = { quarterTurns = (quarterTurns + 1) % 4 }
            // Show the bubble's preview immediately, then swap in full quality.
            if let path = preview.file.localPath {
                image = await ImageLoader.shared.load(path: path, maxPixel: 1600)
            }
            if let full = await model.fetch(photo.full, priority: 32), let path = full.localPath {
                image = await ImageLoader.shared.load(path: path, maxPixel: 4096)
            }
        }
    }

    private func rotated(_ image: NSImage) -> NSImage {
        guard quarterTurns != 0 else { return image }
        let degrees = CGFloat(quarterTurns) * -90
        let size = quarterTurns % 2 == 1 ? NSSize(width: image.size.height, height: image.size.width) : image.size
        return NSImage(size: size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: degrees)
            transform.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
            transform.concat()
            image.draw(in: NSRect(origin: .zero, size: image.size))
            return true
        }
    }
}

/// NSScrollView's native magnification: trackpad pinch, smooth scrolling while
/// zoomed, and double-click to toggle 2×. Content stays centred when smaller
/// than the window.
private struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage
    let commands: PhotoZoomCommands

    final class CenteringClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var rect = super.constrainBoundsRect(proposedBounds)
            guard let document = documentView else { return rect }
            if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
            if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
            return rect
        }
    }

    /// Gesture-recognizer actions are delivered on the main thread.
    @MainActor
    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?

        @objc func doubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scrollView else { return }
            let point = recognizer.location(in: scrollView.documentView)
            let target: CGFloat = scrollView.magnification > 1.01 ? 1 : 2.5
            scrollView.animator().setMagnification(target, centeredAt: point)
            if target == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { (scrollView as? FitScrollView)?.fit() }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps the image fitted to the visible area whenever it is not zoomed,
    /// on every layout — window resizes and full screen included — so a
    /// photo is never larger than the screen and never cropped.
    final class FitScrollView: NSScrollView {
        override func layout() {
            super.layout()
            fit()
        }

        func fit() {
            guard magnification <= 1.001, let document = documentView else { return }
            let size = contentView.bounds.size
            if document.frame.size != size { document.frame = NSRect(origin: .zero, size: size) }
        }

        /// A mouse wheel zooms, like Telegram's viewer; a trackpad scrolls
        /// (pinch zooms).
        override func scrollWheel(with event: NSEvent) {
            guard !event.hasPreciseScrollingDeltas, event.scrollingDeltaY != 0 else {
                super.scrollWheel(with: event)
                return
            }
            let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.15 : 1 / 1.15
            let target = min(maxMagnification, max(minMagnification, magnification * factor))
            let point = documentView?.convert(event.locationInWindow, from: nil) ?? .zero
            setMagnification(target, centeredAt: point)
            if target <= 1.001 { fit() }
        }

        override func endGesture(with event: NSEvent) {
            super.endGesture(with: event)
            if magnification <= 1.001 { fit() }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FitScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 8
        scrollView.usesPredominantAxisScrolling = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        scrollView.documentView = imageView

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        context.coordinator.scrollView = scrollView
        commands.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }
        if imageView.image !== image { imageView.image = image }
        (scrollView as? FitScrollView)?.fit()
        commands.scrollView = scrollView
    }
}

// MARK: - Video

/// Owns the AVPlayer for the viewer: streaming, ±10 s, speed, and resuming
/// where the user left off.
@MainActor
@Observable
final class VideoPlaybackController {
    var player: AVPlayer?
    var isPlaying = false
    var currentTime: Double = 0
    var duration: Double = 0
    var rate: Float = 1
    var resumedFrom: Double?
    var failure: String?

    @ObservationIgnored private var loader: StreamingAssetLoader?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var uniqueID = ""
    @ObservationIgnored private var lastSaved: Double = 0

    func load(video: VideoMedia, model: AppModel) async {
        teardown()
        uniqueID = video.file.uniqueID
        duration = Double(video.duration)
        AudioPlayback.shared.pause()

        let asset: AVURLAsset
        let current = model.files.current(video.file.id) ?? video.file
        if let path = current.localPath {
            asset = AVURLAsset(url: URL(fileURLWithPath: path))
        } else if let source = model.byteSource {
            // Not downloaded: stream byte ranges on demand, so playback — and
            // seeking anywhere — starts without waiting for the whole file.
            let loader = StreamingAssetLoader(
                source: source, fileID: video.file.id, size: video.file.size,
                mimeType: video.mimeType.isEmpty ? "video/mp4" : video.mimeType)
            self.loader = loader
            let ext = (video.fileName as NSString).pathExtension
            asset = loader.makeAsset(fileExtension: ext.isEmpty ? "mp4" : ext)
        } else {
            failure = "Not connected."
            return
        }

        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.currentTime = seconds
                self.isPlaying = player.timeControlStatus != .paused
                if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                // Persist every few seconds, not every tick.
                if abs(seconds - self.lastSaved) >= 3 {
                    self.lastSaved = seconds
                    PlaybackPositionStore.save(seconds, for: self.uniqueID, duration: self.duration)
                }
            }
        }

        if let resume = PlaybackPositionStore.resumePosition(for: uniqueID, duration: duration) {
            await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: .zero)
            resumedFrom = resume
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.resumedFrom = nil
            }
        }
        player.rate = rate
        player.play()
        isPlaying = true
    }

    func togglePlay() {
        guard let player else { return }
        if player.timeControlStatus == .paused {
            player.play()
            player.rate = rate
            isPlaying = true
        } else {
            player.pause()
            isPlaying = false
        }
    }

    func skip(_ seconds: Double) {
        guard let player else { return }
        let now = player.currentTime().seconds
        let target = max(0, min(duration > 0 ? duration - 0.5 : .greatestFiniteMagnitude, (now.isFinite ? now : 0) + seconds))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if let player, player.timeControlStatus != .paused { player.rate = newRate }
    }

    func startOver() {
        player?.seek(to: .zero)
        resumedFrom = nil
        player?.play()
    }

    func teardown() {
        if let player {
            let seconds = player.currentTime().seconds
            if seconds.isFinite { PlaybackPositionStore.save(seconds, for: uniqueID, duration: duration) }
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            player.pause()
        }
        timeObserver = nil
        player = nil
        loader = nil
        isPlaying = false
        currentTime = 0
        resumedFrom = nil
        failure = nil
    }
}

private struct VideoViewer: View {
    let message: Message
    let video: VideoMedia
    let model: AppModel
    let controller: VideoPlaybackController

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let player = controller.player {
                    NativePlayerView(player: player)
                } else if let failure = controller.failure {
                    Text(failure).foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .overlay(alignment: .top) {
                if let resumed = controller.resumedFrom {
                    HStack(spacing: 10) {
                        Text("Resumed at \(formatDuration(resumed))")
                        Button("Start over") { controller.startOver() }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.top, 10)
                    .transition(.opacity)
                }
            }

            controls
        }
        .task(id: message.id) {
            await controller.load(video: video, model: model)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Text(formatDuration(controller.currentTime))
                .frame(width: 64, alignment: .trailing)

            Button { controller.skip(-10) } label: {
                Image(systemName: "gobackward.10").font(.system(size: 20))
            }
            .help("Back 10 seconds (←)")

            Button { controller.togglePlay() } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22))
                    .frame(width: 30)
            }
            .help("Play/Pause (space)")

            Button { controller.skip(10) } label: {
                Image(systemName: "goforward.10").font(.system(size: 20))
            }
            .help("Forward 10 seconds (→)")

            Text(formatDuration(controller.duration))
                .frame(width: 64, alignment: .leading)

            Menu {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2] as [Float], id: \.self) { value in
                    Button {
                        controller.setRate(value)
                    } label: {
                        if value == controller.rate { Label("\(rateText(value))", systemImage: "checkmark") }
                        else { Text(rateText(value)) }
                    }
                }
            } label: {
                Text(rateText(controller.rate))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Playback speed")
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func rateText(_ rate: Float) -> String {
        rate == 1 ? "1×" : String(format: "%g×", rate)
    }
}

/// AVKit's own player view: native scrubbing (drag anywhere to jump there),
/// full screen, and Picture in Picture.
private struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
