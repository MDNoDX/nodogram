//  The right-click menu for a message.
//
//  Laid out like Telegram's: a row of reactions on top (a native macOS menu
//  palette), then the actions. Items appear only when they can work — no
//  greyed-out promises.

import SwiftUI
import AppKit
import NodogramDomain
import NodogramUI

struct MessageMenu: View {
    let model: AppModel
    let message: Message
    /// Reactions this chat allows, loaded when the chat opened.
    let reactions: [ReactionSummary.Kind]
    let onTranslate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if !reactions.isEmpty, !message.isDeleted, !message.isService {
            ControlGroup {
                ForEach(Array(reactions.prefix(7)), id: \.self) { kind in
                    Button {
                        model.toggleReaction(kind, on: message)
                    } label: {
                        reactionLabel(kind)
                    }
                }
            }
            .controlGroupStyle(.palette)
            Divider()
        }

        if !message.isDeleted, model.selectedChat?.canPost ?? true {
            Button {
                model.reply(to: message)
            } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        }

        if !message.text.isEmpty, !message.isDeleted {
            Button(action: onTranslate) { Label("Translate", systemImage: "translate") }
        }

        if !message.text.isEmpty {
            Button {
                model.copyText(of: [message])
            } label: { Label("Copy Text", systemImage: "doc.on.doc") }
            .disabled(!message.canBeSaved && !message.isDeleted)
        }

        if isLinkable, !message.isDeleted {
            Button {
                model.copyLink(to: message)
            } label: { Label("Copy Message Link", systemImage: "link") }
        }

        if !message.isService {
            Button {
                model.toggleStar(message)
            } label: {
                model.isStarred(message)
                    ? Label("Unstar", systemImage: "star.slash")
                    : Label("Star", systemImage: "star")
            }
        }

        if !message.isDeleted {
            Divider()
            if message.canBeSaved {
                Menu {
                    ForEach(recentTargets) { chat in
                        Button(chat.title) {
                            model.completeForward(
                                ForwardRequest(sourceChat: message.chatID, messageIDs: [message.id], hasCaptions: false),
                                to: [chat.id], options: ForwardOptions())
                        }
                    }
                    if !recentTargets.isEmpty { Divider() }
                    Button("Choose Chat…") { model.forward([message]) }
                } label: {
                    Label("Forward", systemImage: "arrowshape.turn.up.right")
                }
            }

            Button {
                model.beginSelection(with: message)
            } label: { Label("Select", systemImage: "checkmark.circle") }

            if message.isOutgoing, message.media == nil || !message.text.isEmpty, message.poll == nil {
                Button {
                    model.edit(message)
                } label: { Label("Edit", systemImage: "pencil") }
            }

            if message.media != nil {
                Divider()
                MediaActions.menu(for: message, model: model)
            }

            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete…", systemImage: "trash")
            }
        }
    }

    /// Message links exist for channels and public groups.
    private var isLinkable: Bool {
        switch model.chatsByID[message.chatID]?.kind {
        case .channel, .supergroup: return true
        default: return false
        }
    }

    /// The chats you write in most, for one-click forwarding.
    private var recentTargets: [Chat] {
        model.chatsByID.values
            .filter { $0.order != 0 && $0.canPost && $0.id != message.chatID }
            .sorted { $0.order > $1.order }
            .prefix(6)
            .map { $0 }
    }

    @ViewBuilder
    private func reactionLabel(_ kind: ReactionSummary.Kind) -> some View {
        switch kind {
        case .emoji(let emoji):
            Image(nsImage: EmojiImage.image(emoji))
        case .customEmoji(let id):
            if let path = model.customEmoji[id], let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
            } else {
                Image(nsImage: EmojiImage.image("✨"))
            }
        case .paid:
            Image(nsImage: EmojiImage.image("⭐️"))
        }
    }
}
