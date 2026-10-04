//  TDLib media → domain media.

import Foundation
import NodogramDomain
import TDLibKit

enum MediaMapping {

    static func file(_ file: TDLibKit.File) -> MediaFile {
        let local = file.local
        let complete = local.isDownloadingCompleted && !local.path.isEmpty
        return MediaFile(
            id: file.id,
            uniqueID: file.remote.uniqueId,
            size: file.size > 0 ? file.size : file.expectedSize,
            downloadedSize: local.downloadedSize,
            isDownloading: local.isDownloadingActive,
            localPath: complete ? local.path : nil
        )
    }

    static func media(_ content: MessageContent) -> MessageMedia? {
        switch content {
        case .messagePhoto(let v):
            return photo(v.photo).map(MessageMedia.photo)

        case .messageVideo(let v):
            let video = v.video
            return .video(VideoMedia(
                file: file(video.video),
                thumbnail: displayableThumbnail(video.thumbnail),
                minithumbnail: video.minithumbnail?.data,
                width: video.width, height: video.height, duration: video.duration,
                mimeType: video.mimeType, fileName: video.fileName,
                supportsStreaming: video.supportsStreaming,
                cover: v.cover.flatMap(photo).map(\.preview)))

        case .messageAnimation(let v):
            let anim = v.animation
            return .animation(VideoMedia(
                file: file(anim.animation),
                thumbnail: displayableThumbnail(anim.thumbnail),
                minithumbnail: anim.minithumbnail?.data,
                width: anim.width, height: anim.height, duration: anim.duration,
                mimeType: anim.mimeType, fileName: anim.fileName,
                supportsStreaming: true))

        case .messageVideoNote(let v):
            let note = v.videoNote
            return .videoNote(VideoNoteMedia(
                file: file(note.video),
                thumbnail: displayableThumbnail(note.thumbnail),
                minithumbnail: note.minithumbnail?.data,
                duration: note.duration, length: note.length))

        case .messageVoiceNote(let v):
            let voice = v.voiceNote
            return .voiceNote(VoiceNoteMedia(
                file: file(voice.voice), duration: voice.duration,
                waveform: waveform(voice.waveform), mimeType: voice.mimeType))

        case .messageAudio(let v):
            let audio = v.audio
            return .audio(AudioMedia(
                file: file(audio.audio), duration: audio.duration,
                title: audio.title, performer: audio.performer,
                fileName: audio.fileName, mimeType: audio.mimeType))

        case .messageDocument(let v):
            let doc = v.document
            return .document(DocumentMedia(
                file: file(doc.document), fileName: doc.fileName,
                mimeType: doc.mimeType, thumbnail: displayableThumbnail(doc.thumbnail)))

        case .messageSticker(let v):
            let sticker = v.sticker
            let format: StickerMedia.Format = {
                switch sticker.format {
                case .stickerFormatWebp: return .still
                case .stickerFormatTgs: return .animated
                case .stickerFormatWebm: return .video
                }
            }()
            return .sticker(StickerMedia(
                file: file(sticker.sticker),
                thumbnail: displayableThumbnail(sticker.thumbnail),
                emoji: sticker.emoji, format: format,
                width: sticker.width, height: sticker.height))

        default:
            return nil
        }
    }

    /// Picks two photo variants: a preview big enough to look sharp in a
    /// bubble on a Retina display, and the largest for the viewer.
    static func photo(_ photo: Photo) -> PhotoMedia? {
        let sizes = photo.sizes.sorted { $0.width * $0.height < $1.width * $1.height }
        guard let largest = sizes.last else { return nil }
        let preview = sizes.first { max($0.width, $0.height) >= 1000 } ?? largest
        return PhotoMedia(
            preview: file(preview.photo), full: file(largest.photo),
            width: largest.width, height: largest.height,
            minithumbnail: photo.minithumbnail?.data)
    }

    /// Only formats macOS can draw directly. TGS (Lottie), WebM and MPEG-4
    /// thumbnails are skipped rather than shown broken.
    static func displayableThumbnail(_ thumbnail: Thumbnail?) -> MediaFile? {
        guard let thumbnail else { return nil }
        switch thumbnail.format {
        case .thumbnailFormatJpeg, .thumbnailFormatPng, .thumbnailFormatWebp, .thumbnailFormatGif:
            return file(thumbnail.file)
        default:
            return nil
        }
    }

    /// Telegram packs voice waveforms as 5-bit samples, least significant bit
    /// first, across byte boundaries.
    static func waveform(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        let count = bytes.count * 8 / 5
        var samples = [UInt8]()
        samples.reserveCapacity(count)
        for index in 0..<count {
            let bit = index * 5
            let byte = bit / 8
            var value = UInt16(bytes[byte])
            if byte + 1 < bytes.count { value |= UInt16(bytes[byte + 1]) << 8 }
            samples.append(UInt8((value >> UInt16(bit % 8)) & 0x1F))
        }
        return samples
    }

    static func entities(_ text: FormattedText) -> [NodogramDomain.TextEntity] {
        text.entities.compactMap { entity in
            let kind: NodogramDomain.TextEntity.Kind
            switch entity.type {
            case .textEntityTypeBold: kind = .bold
            case .textEntityTypeItalic: kind = .italic
            case .textEntityTypeUnderline: kind = .underline
            case .textEntityTypeStrikethrough: kind = .strikethrough
            case .textEntityTypeSpoiler: kind = .spoiler
            case .textEntityTypeCode: kind = .code
            case .textEntityTypePre: kind = .pre(language: nil)
            case .textEntityTypePreCode(let v): kind = .pre(language: v.language.isEmpty ? nil : v.language)
            case .textEntityTypeBlockQuote, .textEntityTypeExpandableBlockQuote: kind = .quote
            case .textEntityTypeUrl: kind = .url
            case .textEntityTypeTextUrl(let v): kind = .textLink(v.url)
            case .textEntityTypeEmailAddress: kind = .email
            case .textEntityTypePhoneNumber: kind = .phone
            case .textEntityTypeMention: kind = .mention
            case .textEntityTypeMentionName(let v): kind = .mentionName(userID: v.userId)
            case .textEntityTypeHashtag: kind = .hashtag
            case .textEntityTypeCashtag: kind = .cashtag
            case .textEntityTypeBotCommand: kind = .botCommand
            default: return nil
            }
            return NodogramDomain.TextEntity(offset: entity.offset, length: entity.length, kind: kind)
        }
    }
}
