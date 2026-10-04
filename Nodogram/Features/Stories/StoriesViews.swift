//  Stories: the strip of rings above the chat list, and the full-window viewer.
//
//  Opening a story tells Telegram it was seen (the owner sees you in its
//  viewers), exactly as the official apps do — so nothing is opened except
//  when the user clicks.

import AVFoundation
import AVKit
import SwiftUI
import NodogramDomain
import NodogramPlatform
import NodogramUI

struct StoriesStrip: View {
    let model: AppModel

    var body: some View {
        let owners = model.orderedStoryOwners
        if !owners.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(owners) { owner in
                        if let chat = model.chatsByID[owner.chatID] {
                            Button {
                                model.openStories(from: owner.chatID)
                            } label: {
                                VStack(spacing: 4) {
                                    Avatar(title: chat.title, seed: chat.id.rawValue, size: 46,
                                           imagePath: chat.avatarPath, thumbnail: chat.avatarThumbnail,
                                           isSavedMessages: chat.isSavedMessages)
                                        .padding(3)
                                        .overlay {
                                            Circle().strokeBorder(
                                                owner.hasUnread
                                                    ? AnyShapeStyle(LinearGradient(
                                                        colors: [Theme.accent, Color(red: 0.36, green: 0.85, blue: 0.62)],
                                                        startPoint: .topTrailing, endPoint: .bottomLeading))
                                                    : AnyShapeStyle(Color.secondary.opacity(0.35)),
                                                lineWidth: owner.hasUnread ? 2.5 : 1.5)
                                        }
                                    Text(chat.isSavedMessages ? "My Story" : chat.title)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(owner.hasUnread ? .primary : .secondary)
                                        .lineLimit(1)
                                        .frame(width: 58)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(chat.title)
                            .onAppear { model.ensureAvatar(for: chat.id) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

// MARK: - Viewer

struct StoryViewerOverlay: View {
    let model: AppModel

    @State private var item: StoryItem?
    @State private var isLoading = false
    @State private var progress: Double = 0
    @State private var player: AVPlayer?
    @State private var loader: StreamingAssetLoader?
    @State private var isPaused = false
    @State private var keyMonitor: Any?

    private static let photoDuration: Double = 6

    var body: some View {
        if let state = model.storyViewer,
           state.ownerIndex < state.owners.count,
           let owner = model.storyOwners[state.owners[state.ownerIndex]] {
            let ids = owner.storyIDs
            let storyID = ids.indices.contains(state.storyIndex) ? ids[state.storyIndex] : ids.first ?? 0
            ZStack {
                Color.black.opacity(0.95).ignoresSafeArea()
                    .onTapGesture { close(owner: owner.chatID, story: storyID) }

                GeometryReader { geo in
                    let height = geo.size.height - 40
                    let width = min(height * 9 / 16, geo.size.width - 40)
                    card(owner: owner, ids: ids, state: state, storyID: storyID)
                        .frame(width: width, height: width * 16 / 9)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .transition(.opacity)
            .task(id: "\(owner.chatID.rawValue)-\(storyID)") { await load(storyID, of: owner.chatID) }
            .task(id: "\(owner.chatID.rawValue)-\(storyID)-timer") { await runTimer() }
            .onAppear(perform: installKeys)
            .onDisappear {
                removeKeys()
                teardown()
            }
        }
    }

    private func card(owner: StoryOwner, ids: [Int], state: StoryViewerState, storyID: Int) -> some View {
        ZStack {
            Color(white: 0.08)
            content
            // Tap zones: left third goes back, the rest forward.
            HStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity)
                    .onTapGesture { step(-1) }
                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity)
                    .onTapGesture { step(1) }
                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity)
                    .onTapGesture { step(1) }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(ids.indices, id: \.self) { index in
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.3))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: geo.size.width * fill(index, current: state.storyIndex))
                                }
                        }
                        .frame(height: 2.5)
                    }
                }
                header(owner: owner, storyID: storyID)
            }
            .padding(10)
            .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .bottom) {
            if let item, !item.caption.isEmpty {
                Text(FormattedText.attributed(item.caption, entities: item.entities, baseSize: 13.5))
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.5), radius: 30)
    }

    private func header(owner: StoryOwner, storyID: Int) -> some View {
        let chat = model.chatsByID[owner.chatID]
        return HStack(spacing: 8) {
            Avatar(title: chat?.title ?? "", seed: owner.chatID.rawValue, size: 30,
                   imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
            VStack(alignment: .leading, spacing: 0) {
                Text(chat?.title ?? "").font(.system(size: 13, weight: .semibold))
                if let item {
                    Text(RelativeTimeFormatter.short(item.date)).font(.system(size: 11)).opacity(0.75)
                }
            }
            .foregroundStyle(.white)
            Spacer()
            Button {
                isPaused.toggle()
                if isPaused { player?.pause() } else { player?.play() }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help(isPaused ? "Play" : "Pause")
            Button {
                close(owner: owner.chatID, story: storyID)
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Close (Esc)")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let item {
            switch item.content {
            case .photo(let photo):
                let state = model.files.state(for: photo.full)
                ZStack {
                    MinithumbnailView(data: photo.minithumbnail)
                    LocalImageView(path: model.files.state(for: photo.preview).file.localPath, maxPixel: 1400,
                                   contentMode: .fit) { Color.clear }
                    LocalImageView(path: state.file.localPath, maxPixel: 2200, contentMode: .fit) { Color.clear }
                }
            case .video(let video):
                ZStack {
                    MinithumbnailView(data: video.minithumbnail)
                    if let player { PlayerLayerView(player: player, gravity: .resizeAspect) }
                }
            case .unsupported:
                Text("This story can't be shown here yet.")
                    .foregroundStyle(.white.opacity(0.8))
            }
        } else if isLoading {
            ProgressView().controlSize(.small).tint(.white)
        }
    }

    private func fill(_ index: Int, current: Int) -> Double {
        if index < current { return 1 }
        if index > current { return 0 }
        return min(max(progress, 0), 1)
    }

    // MARK: Loading and timing

    private func load(_ storyID: Int, of owner: ChatID) async {
        teardown()
        item = nil
        progress = 0
        isPaused = false
        isLoading = true
        defer { isLoading = false }
        guard let story = await model.story(storyID, of: owner) else { return }
        item = story
        model.storyOpened(storyID, of: owner)
        switch story.content {
        case .photo(let photo):
            _ = await model.fetch(photo.preview, priority: 32)
            _ = await model.fetch(photo.full, priority: 32)
        case .video(let video):
            let current = model.files.current(video.file.id) ?? video.file
            let asset: AVURLAsset
            if let path = current.localPath {
                asset = AVURLAsset(url: URL(fileURLWithPath: path))
            } else if let source = model.byteSource {
                let loader = StreamingAssetLoader(source: source, fileID: video.file.id, size: video.file.size,
                                                  mimeType: video.mimeType.isEmpty ? "video/mp4" : video.mimeType)
                self.loader = loader
                asset = loader.makeAsset(fileExtension: "mp4")
            } else { return }
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            AudioPlayback.shared.pause()
            player.play()
        case .unsupported:
            break
        }
    }

    private func runTimer() async {
        // Ticks drive the progress bar and auto-advance.
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, !isPaused, let item else { continue }
            switch item.content {
            case .video(let video):
                guard let player, let current = player.currentItem else { continue }
                let total = current.duration.seconds.isFinite ? current.duration.seconds : Double(video.duration)
                guard total > 0 else { continue }
                progress = player.currentTime().seconds / total
                if progress >= 0.995 { step(1); return }
            default:
                progress += 0.05 / Self.photoDuration
                if progress >= 1 { step(1); return }
            }
        }
    }

    private func step(_ delta: Int) {
        guard var state = model.storyViewer else { return }
        let ownerID = state.owners[state.ownerIndex]
        let ids = model.storyOwners[ownerID]?.storyIDs ?? []
        if let item { model.storyClosed(item.id, of: ownerID) }
        let next = state.storyIndex + delta
        if next >= 0, next < ids.count {
            state.storyIndex = next
        } else if delta > 0 {
            guard state.ownerIndex + 1 < state.owners.count else { model.closeStories(); return }
            state.ownerIndex += 1
            state.storyIndex = 0
        } else {
            guard state.ownerIndex > 0 else { progress = 0; return }
            state.ownerIndex -= 1
            let previousIDs = model.storyOwners[state.owners[state.ownerIndex]]?.storyIDs ?? []
            state.storyIndex = max(previousIDs.count - 1, 0)
        }
        model.storyViewer = state
    }

    private func close(owner: ChatID, story: Int) {
        if item != nil { model.storyClosed(story, of: owner) }
        teardown()
        model.closeStories()
    }

    private func teardown() {
        player?.pause()
        player = nil
        loader = nil
    }

    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53:  // esc
                teardown(); model.closeStories(); return nil
            case 123: step(-1); return nil
            case 124: step(1); return nil
            case 49:  // space
                isPaused.toggle()
                if isPaused { player?.pause() } else { player?.play() }
                return nil
            default: return event
            }
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
