//  Stickers and GIFs for the composer picker: fetch the favourite/recent/saved
//  lists, download thumbnails on demand, and send the chosen one.

import Foundation
import NodogramDomain

public struct StickerSections: Sendable {
    public var favorites: [StickerPickItem] = []
    public var recent: [StickerPickItem] = []
    public var gifs: [StickerPickItem] = []
    public var isEmpty: Bool { favorites.isEmpty && recent.isEmpty && gifs.isEmpty }
    public init(favorites: [StickerPickItem] = [], recent: [StickerPickItem] = [], gifs: [StickerPickItem] = []) {
        self.favorites = favorites
        self.recent = recent
        self.gifs = gifs
    }
}

extension AppModel {

    public func stickerSections() async -> StickerSections {
        guard let gateway else { return StickerSections() }
        async let fav = gateway.favoriteStickers()
        async let rec = gateway.recentStickers()
        async let gif = gateway.savedGIFItems()
        return StickerSections(favorites: await fav, recent: await rec, gifs: await gif)
    }

    /// Downloads the thumbnail for one item and returns its local path.
    public func stickerThumb(_ item: StickerPickItem) async -> String? {
        guard let gateway else { return nil }
        return await gateway.downloadAndWait(item.thumbFileID, priority: 20)?.localPath
    }

    public func sendSticker(_ item: StickerPickItem, to chat: ChatID) {
        guard let gateway else { return }
        Task { [weak self] in
            do {
                if item.kind == .gif { try await gateway.sendGIF(item.id, to: chat) }
                else { try await gateway.sendSticker(item.id, to: chat) }
                self?.reloadLatest()
            } catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func clearRecentStickers() {
        guard let gateway else { return }
        Task { [weak self] in
            let n = await gateway.clearRecentStickersList()
            self?.showToast(n > 0 ? "Cleared \(n) recent stickers" : "No recent stickers")
        }
    }
}
