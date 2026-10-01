//  Turns TDLib message content into what Nodogram displays.
//
//  Three kinds of output, kept distinct on purpose:
//    - text a person wrote (a message body or a media caption)
//    - a short label for media ("Photo", "Voice message") shown as a chip
//    - a service action ("joined the group") rendered as a centred line
//
//  Content types Nodogram cannot render yet still get an honest label, never an
//  empty bubble — an empty bubble reads as a bug, a label reads as a limit.

import Foundation
import NodogramDomain
import TDLibKit

struct MappedContent: Equatable {
    var text: String
    var attachmentLabel: String?
    var isService: Bool = false
    var entities: [NodogramDomain.TextEntity] = []
}

enum ContentMapping {

    static func map(_ content: MessageContent) -> MappedContent {
        switch content {
        // Text and media
        case .messageText(let v):
            return .init(text: v.text.text, entities: MediaMapping.entities(v.text))
        case .messagePhoto(let v):
            return .init(text: v.caption.text, attachmentLabel: "Photo", entities: MediaMapping.entities(v.caption))
        case .messageVideo(let v):
            return .init(text: v.caption.text, attachmentLabel: "Video", entities: MediaMapping.entities(v.caption))
        case .messageAnimation(let v):
            return .init(text: v.caption.text, attachmentLabel: "GIF", entities: MediaMapping.entities(v.caption))
        case .messageDocument(let v):
            let name = v.document.fileName
            return .init(text: v.caption.text, attachmentLabel: name.isEmpty ? "Document" : name, entities: MediaMapping.entities(v.caption))
        case .messageAudio(let v):
            return .init(text: v.caption.text, attachmentLabel: "Audio", entities: MediaMapping.entities(v.caption))
        case .messageVoiceNote(let v):
            return .init(text: v.caption.text, attachmentLabel: "Voice message", entities: MediaMapping.entities(v.caption))
        case .messageVideoNote:
            return .init(text: "", attachmentLabel: "Video message")
        case .messageSticker(let v):
            let emoji = v.sticker.emoji
            return .init(text: "", attachmentLabel: emoji.isEmpty ? "Sticker" : "\(emoji) Sticker")
        case .messageAnimatedEmoji(let v):
            return .init(text: v.emoji)
        case .messageDice(let v):
            return .init(text: v.emoji)
        case .messageLocation, .messageLiveLocation, .messageVenue:
            return .init(text: "", attachmentLabel: "Location")
        case .messageContact:
            return .init(text: "", attachmentLabel: "Contact")
        case .messagePoll:
            return .init(text: "", attachmentLabel: "Poll")
        case .messageChecklist:
            return .init(text: "", attachmentLabel: "Checklist")
        case .messageStory:
            return .init(text: "", attachmentLabel: "Story")
        case .messageGame:
            return .init(text: "", attachmentLabel: "Game")
        case .messageInvoice:
            return .init(text: "", attachmentLabel: "Invoice")
        case .messagePaidMedia:
            return .init(text: "", attachmentLabel: "Paid media")
        case .messageExpiredPhoto:
            return .init(text: "", attachmentLabel: "Photo has expired")
        case .messageExpiredVideo, .messageExpiredVideoNote:
            return .init(text: "", attachmentLabel: "Video has expired")
        case .messageExpiredVoiceNote:
            return .init(text: "", attachmentLabel: "Voice message has expired")
        case .messageCall(let v):
            let kind = v.isVideo ? "Video call" : "Call"
            let minutes = v.duration / 60, seconds = v.duration % 60
            let length = v.duration > 0 ? String(format: " · %d:%02d", minutes, seconds) : ""
            return .init(text: "", attachmentLabel: kind + length)

        // Service events — the actor's name is prepended by the UI.
        case .messageBasicGroupChatCreate, .messageSupergroupChatCreate:
            return service("created the group")
        case .messageChatChangeTitle(let v):
            return service("changed the name to “\(v.title)”")
        case .messageChatChangePhoto:
            return service("changed the group photo")
        case .messageChatDeletePhoto:
            return service("removed the group photo")
        case .messageChatAddMembers:
            return service("added members")
        case .messageChatJoinByLink:
            return service("joined via invite link")
        case .messageChatJoinByRequest:
            return service("joined the group")
        case .messageChatDeleteMember:
            return service("left the group")
        case .messagePinMessage:
            return service("pinned a message")
        case .messageScreenshotTaken:
            return service("took a screenshot")
        case .messageContactRegistered:
            return service("joined Telegram")
        case .messageChatSetMessageAutoDeleteTime:
            return service("changed the auto-delete timer")
        case .messageChatUpgradeTo, .messageChatUpgradeFrom:
            return service("upgraded the group")
        case .messageVideoChatStarted:
            return service("started a video chat")
        case .messageVideoChatEnded:
            return service("ended the video chat")
        case .messageVideoChatScheduled:
            return service("scheduled a video chat")
        case .messageGroupCall:
            return service("started a group call")
        case .messageForumTopicCreated:
            return service("created a topic")
        case .messageGift, .messageUpgradedGift:
            return service("sent a gift")
        case .messageChatSetTheme, .messageChatSetBackground:
            return service("changed the chat theme")
        case .messageChatBoost:
            return service("boosted the group")

        case .messageUnsupported:
            return .init(text: "", attachmentLabel: "Message not supported by this version")
        default:
            return .init(text: "", attachmentLabel: "Unsupported message")
        }
    }

    private static func service(_ action: String) -> MappedContent {
        .init(text: action, attachmentLabel: nil, isService: true)
    }
}
