//  A sticker or GIF offered in the composer's picker: enough to show a
//  thumbnail and to send the original by its remote file id.

import Foundation

public struct StickerPickItem: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable { case sticker, gif }
    public let id: String        // remote file id, used to send
    public let kind: Kind
    public let thumbFileID: Int  // TDLib file id to download for the thumbnail
    public let emoji: String
    public let isAnimated: Bool
    public var thumbnailPath: String?

    public init(id: String, kind: Kind, thumbFileID: Int, emoji: String,
                isAnimated: Bool, thumbnailPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.thumbFileID = thumbFileID
        self.emoji = emoji
        self.isAnimated = isAnimated
        self.thumbnailPath = thumbnailPath
    }
}
