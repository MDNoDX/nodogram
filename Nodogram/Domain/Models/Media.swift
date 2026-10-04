//  Media vocabulary.
//
//  These describe what a message carries, not how it is fetched. TDLib's file
//  ids live here only as opaque numbers; how bytes arrive is the gateway's
//  business, behind `MediaByteSource`.

import Foundation

/// One downloadable file, as known at a moment in time. Live progress is
/// tracked separately (see FileStore in the features layer), so a message
/// snapshot never has to be rebuilt just because a download advanced.
public struct MediaFile: Hashable, Sendable {
    /// TDLib's file id. Valid for the current session only.
    public let id: Int
    /// Telegram's remote unique id. Stable across sessions and devices, so it
    /// keys anything that must survive a restart, such as playback positions.
    public let uniqueID: String
    /// Total size in bytes, or the best estimate TDLib has (0 if unknown).
    public var size: Int64
    public var downloadedSize: Int64
    public var isDownloading: Bool
    /// Set only once the whole file is on disk.
    public var localPath: String?

    public init(id: Int, uniqueID: String, size: Int64, downloadedSize: Int64 = 0,
                isDownloading: Bool = false, localPath: String? = nil) {
        self.id = id
        self.uniqueID = uniqueID
        self.size = size
        self.downloadedSize = downloadedSize
        self.isDownloading = isDownloading
        self.localPath = localPath
    }

    public var isComplete: Bool { localPath != nil }

    /// 0…1, or nil when the size is unknown.
    public var progress: Double? {
        guard size > 0 else { return nil }
        return min(1, Double(downloadedSize) / Double(size))
    }
}

public enum MessageMedia: Hashable, Sendable {
    case photo(PhotoMedia)
    case video(VideoMedia)
    /// Telegram "GIFs" are silent, looping MP4s.
    case animation(VideoMedia)
    /// Round video messages.
    case videoNote(VideoNoteMedia)
    case voiceNote(VoiceNoteMedia)
    case audio(AudioMedia)
    case document(DocumentMedia)
    case sticker(StickerMedia)
}

public struct PhotoMedia: Hashable, Sendable {
    /// A mid-sized variant for the bubble — quick to download.
    public let preview: MediaFile
    /// The largest variant, for the full-screen viewer.
    public let full: MediaFile
    public let width: Int
    public let height: Int
    /// Tiny inline JPEG, shown blurred before anything downloads.
    public let minithumbnail: Data?

    public init(preview: MediaFile, full: MediaFile, width: Int, height: Int, minithumbnail: Data?) {
        self.preview = preview; self.full = full
        self.width = width; self.height = height; self.minithumbnail = minithumbnail
    }
}

public struct VideoMedia: Hashable, Sendable {
    public let file: MediaFile
    public let thumbnail: MediaFile?
    public let minithumbnail: Data?
    public let width: Int
    public let height: Int
    /// Seconds.
    public let duration: Int
    public let mimeType: String
    public let fileName: String
    /// Whether the file is laid out for playback before it fully downloads.
    public let supportsStreaming: Bool
    /// A full-resolution cover image the sender attached, when there is one —
    /// far sharper than the small thumbnail.
    public let cover: MediaFile?

    public init(file: MediaFile, thumbnail: MediaFile?, minithumbnail: Data?, width: Int, height: Int,
                duration: Int, mimeType: String, fileName: String, supportsStreaming: Bool,
                cover: MediaFile? = nil) {
        self.file = file; self.thumbnail = thumbnail; self.minithumbnail = minithumbnail
        self.width = width; self.height = height; self.duration = duration
        self.mimeType = mimeType; self.fileName = fileName; self.supportsStreaming = supportsStreaming
        self.cover = cover
    }
}

public struct VideoNoteMedia: Hashable, Sendable {
    public let file: MediaFile
    public let thumbnail: MediaFile?
    public let minithumbnail: Data?
    public let duration: Int
    /// Diameter in pixels.
    public let length: Int

    public init(file: MediaFile, thumbnail: MediaFile?, minithumbnail: Data?, duration: Int, length: Int) {
        self.file = file; self.thumbnail = thumbnail; self.minithumbnail = minithumbnail
        self.duration = duration; self.length = length
    }
}

public struct VoiceNoteMedia: Hashable, Sendable {
    public let file: MediaFile
    public let duration: Int
    /// Amplitude samples, each 0…31, as Telegram encodes them.
    public let waveform: [UInt8]
    public let mimeType: String

    public init(file: MediaFile, duration: Int, waveform: [UInt8], mimeType: String) {
        self.file = file; self.duration = duration; self.waveform = waveform; self.mimeType = mimeType
    }
}

public struct AudioMedia: Hashable, Sendable {
    public let file: MediaFile
    public let duration: Int
    public let title: String
    public let performer: String
    public let fileName: String
    public let mimeType: String

    public init(file: MediaFile, duration: Int, title: String, performer: String, fileName: String, mimeType: String) {
        self.file = file; self.duration = duration; self.title = title
        self.performer = performer; self.fileName = fileName; self.mimeType = mimeType
    }
}

public struct DocumentMedia: Hashable, Sendable {
    public let file: MediaFile
    public let fileName: String
    public let mimeType: String
    public let thumbnail: MediaFile?

    public init(file: MediaFile, fileName: String, mimeType: String, thumbnail: MediaFile?) {
        self.file = file; self.fileName = fileName; self.mimeType = mimeType; self.thumbnail = thumbnail
    }
}

public struct StickerMedia: Hashable, Sendable {
    public enum Format: Hashable, Sendable { case still, animated, video }
    public let file: MediaFile
    /// A still image every sticker kind has; used for animated and video
    /// stickers, whose native formats (TGS, WebM) macOS cannot render.
    public let thumbnail: MediaFile?
    public let emoji: String
    public let format: Format
    public let width: Int
    public let height: Int

    public init(file: MediaFile, thumbnail: MediaFile?, emoji: String, format: Format, width: Int, height: Int) {
        self.file = file; self.thumbnail = thumbnail; self.emoji = emoji
        self.format = format; self.width = width; self.height = height
    }
}

extension MessageMedia {
    /// The main file, for download, save and "Show in Finder".
    public var primaryFile: MediaFile {
        switch self {
        case .photo(let m): return m.full
        case .video(let m), .animation(let m): return m.file
        case .videoNote(let m): return m.file
        case .voiceNote(let m): return m.file
        case .audio(let m): return m.file
        case .document(let m): return m.file
        case .sticker(let m): return m.file
        }
    }

    /// A sensible file name when saving.
    public var suggestedFileName: String {
        switch self {
        case .photo(let m): return "Photo \(m.full.uniqueID.prefix(8)).jpg"
        case .video(let m), .animation(let m):
            return m.fileName.isEmpty ? "Video \(m.file.uniqueID.prefix(8)).mp4" : m.fileName
        case .videoNote(let m): return "Video message \(m.file.uniqueID.prefix(8)).mp4"
        case .voiceNote(let m): return "Voice message \(m.file.uniqueID.prefix(8)).ogg"
        case .audio(let m): return m.fileName.isEmpty ? "\(m.title.isEmpty ? "Audio" : m.title).mp3" : m.fileName
        case .document(let m): return m.fileName.isEmpty ? "File \(m.file.uniqueID.prefix(8))" : m.fileName
        case .sticker(let m): return "Sticker \(m.file.uniqueID.prefix(8)).webp"
        }
    }
}

/// Supplies file bytes on demand, so video can play from any position before
/// the download finishes. Implemented by the Telegram gateway.
public protocol MediaByteSource: Sendable {
    /// Returns once `length` bytes from `offset` are available locally.
    /// `priority` is 1…32: playback asks for 32, background poster frames low.
    func prepareRange(fileID: Int, offset: Int64, length: Int64, priority: Int) async throws
    func readRange(fileID: Int, offset: Int64, count: Int64) async throws -> Data
}

// MARK: - Text formatting

/// One formatting run in a message, in UTF-16 offsets as Telegram sends them.
public struct TextEntity: Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        case bold, italic, underline, strikethrough, spoiler
        case code
        case pre(language: String?)
        case quote
        case url
        case textLink(String)
        case email
        case phone
        case mention
        case mentionName(userID: Int64)
        case hashtag
        case cashtag
        case botCommand
    }

    public let offset: Int
    public let length: Int
    public let kind: Kind

    public init(offset: Int, length: Int, kind: Kind) {
        self.offset = offset; self.length = length; self.kind = kind
    }
}

// MARK: - Chat actions

/// What someone is doing in a chat right now — "typing…", "recording a voice
/// message…". Telegram expires these after a few seconds unless renewed.
public enum ChatActivity: Hashable, Sendable {
    case typing
    case recordingVoice
    case recordingVideoNote
    case uploadingPhoto
    case uploadingVideo
    case uploadingFile
    case choosingSticker
    case other

    public var phrase: String {
        switch self {
        case .typing: return "typing"
        case .recordingVoice: return "recording a voice message"
        case .recordingVideoNote: return "recording a video message"
        case .uploadingPhoto: return "sending a photo"
        case .uploadingVideo: return "sending a video"
        case .uploadingFile: return "sending a file"
        case .choosingSticker: return "choosing a sticker"
        case .other: return "busy"
        }
    }
}
