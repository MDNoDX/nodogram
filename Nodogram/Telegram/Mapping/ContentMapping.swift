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
        case .messagePoll(let v):
            // The question doubles as the message text, so chat previews,
            // search and the deleted-message archive all see something useful.
            let isQuiz: Bool = { if case .pollTypeQuiz = v.poll.type { return true }; return false }()
            return .init(text: v.poll.question.text, attachmentLabel: isQuiz ? "Quiz" : "Poll",
                         entities: MediaMapping.entities(v.poll.question))
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

        // Content added in 2025–2026
        case .messageRichMessage(let v):
            let text = richText(v.message.blocks)
            return .init(text: text, attachmentLabel: text.isEmpty ? "Article" : nil)
        case .messageStakeDice:
            return .init(text: "", attachmentLabel: "🎲 Dice")
        case .messageGameScore:
            return service("scored in a game")
        case .messageGiveaway, .messageGiveawayCreated:
            return .init(text: "", attachmentLabel: "🎁 Giveaway")
        case .messageGiveawayCompleted, .messageGiveawayWinners:
            return service("finished a giveaway")
        case .messageGiveawayPrizeStars, .messageGiftedStars, .messageGiftedGrams:
            return service("sent a gift")
        case .messageGiftedPremium, .messagePremiumGiftCode:
            return service("gifted Telegram Premium")
        case .messageChecklistTasksAdded:
            return service("added tasks to a checklist")
        case .messageChecklistTasksDone:
            return service("completed tasks in a checklist")
        case .messagePollOptionAdded:
            return service("added a poll option")
        case .messagePollOptionDeleted:
            return service("removed a poll option")
        case .messageCustomServiceAction(let v):
            return service(v.text)
        case .messageChatOwnerChanged:
            return service("transferred ownership")
        case .messageChatOwnerLeft:
            return service("left; ownership passed on")
        case .messageChatHasProtectedContentToggled, .messageChatHasProtectedContentDisableRequested:
            return service("changed content protection")
        case .messageChatAddedToCommunity, .messageChatJoinFromCommunity:
            return service("joined a community")
        case .messageChatRemovedFromCommunity:
            return service("left a community")
        case .messageForumTopicEdited, .messageForumTopicIsClosedToggled, .messageForumTopicIsHiddenToggled:
            return service("updated a topic")
        case .messageInviteVideoChatParticipants:
            return service("invited members to the video chat")
        case .messageProximityAlertTriggered:
            return service("is nearby")
        case .messageSuggestBirthdate:
            return service("suggested a birthday")
        case .messageSuggestProfilePhoto:
            return service("suggested a profile photo")
        case .messageBotWriteAccessAllowed:
            return service("allowed the bot to message")
        case .messageManagedBotCreated:
            return service("created a bot")
        case .messageChatShared, .messageUsersShared:
            return service("shared a chat")
        case .messageWebAppDataSent, .messageWebAppDataReceived:
            return service("used a mini app")
        case .messagePaymentSuccessful, .messagePaymentSuccessfulBot:
            return service("made a payment")
        case .messagePaymentRefunded, .messagePaidMessagesRefunded, .messageRefundedUpgradedGift:
            return service("received a refund")
        case .messagePaidMessagePriceChanged, .messageDirectMessagePriceChanged:
            return service("changed the message price")
        case .messageSuggestedPostApproved, .messageSuggestedPostPaid:
            return service("approved a suggested post")
        case .messageSuggestedPostDeclined, .messageSuggestedPostApprovalFailed, .messageSuggestedPostRefunded:
            return service("declined a suggested post")
        case .messageUpgradedGiftPurchaseOffer, .messageUpgradedGiftPurchaseOfferRejected:
            return service("made a gift offer")
        case .messagePassportDataSent, .messagePassportDataReceived:
            return service("shared Telegram Passport data")

        case .messageUnsupported:
            return .init(text: "", attachmentLabel: "Newer message type — open it on your phone")
        @unknown default:
            // A type added by a newer TDLib: label it rather than fail.
            return .init(text: "", attachmentLabel: "Message")
        }
    }

    /// The readable text of an article-style message, block by block. Built
    /// by reflection so every kind of block and inline style contributes its
    /// words, in order, without a case per TDLib type; links' URLs are left out.
    static func richText(_ blocks: [PageBlock]) -> String {
        func collect(_ value: Any, into parts: inout [String]) {
            let mirror = Mirror(reflecting: value)
            for child in mirror.children {
                if child.label == "url" || child.label == "anchorName" || child.label == "language" { continue }
                if let string = child.value as? String {
                    if child.label == "text" || child.label == nil { parts.append(string) }
                } else {
                    collect(child.value, into: &parts)
                }
            }
        }
        return blocks.compactMap { block -> String? in
            var parts: [String] = []
            collect(block, into: &parts)
            let line = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        .joined(separator: "\n\n")
    }

    private static func service(_ action: String) -> MappedContent {
        .init(text: action, attachmentLabel: nil, isService: true)
    }
}
