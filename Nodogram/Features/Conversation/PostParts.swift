//  The parts of a message around its content: who it was forwarded from, the
//  quote it replies to, reactions, the comments bar and the sponsored message.

import SwiftUI
import NodogramDomain
import NodogramUI

/// "Forwarded from Kino Insayder".
struct ForwardedHeader: View {
    let origin: ForwardOrigin

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(.system(size: 9))
            Text("Forwarded from ").foregroundStyle(.secondary) + Text(origin.name).fontWeight(.semibold)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.accent)
        .lineLimit(1)
        .help(origin.date.map { "Originally sent \(RelativeTimeFormatter.exact($0))" } ?? "")
    }
}

/// The quoted message above a reply. Click to jump to it.
struct ReplyQuote: View {
    let preview: ReplyPreview
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.accent)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    if !preview.senderName.isEmpty {
                        Text(preview.senderName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(preview.text.isEmpty ? "Message" : preview.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 8)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to message")
    }
}

/// Reaction pills under a message. Click one to add or remove yours.
struct ReactionsBar: View {
    let model: AppModel
    let message: Message

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(message.reactions, id: \.kind) { reaction in
                Button {
                    model.toggleReaction(reaction.kind, on: message)
                } label: {
                    HStack(spacing: 4) {
                        ReactionGlyph(kind: reaction.kind, model: model, size: 16)
                        Text(compact(reaction.count))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(reaction.isChosen ? Color.white : Theme.accent)
                    .background(reaction.isChosen ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14)),
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(reaction.kind == .paid)
                .help(reaction.isChosen ? "Remove your reaction" : "React")
                .accessibilityLabel("\(reaction.count) reactions\(reaction.isChosen ? ", including yours" : "")")
            }
        }
    }

    private func compact(_ count: Int) -> String {
        count >= 1000 ? count.formatted(.number.notation(.compactName)) : "\(count)"
    }
}

struct ReactionGlyph: View {
    let kind: ReactionSummary.Kind
    let model: AppModel
    let size: CGFloat

    var body: some View {
        switch kind {
        case .emoji(let emoji):
            Text(emoji).font(.system(size: size))
        case .customEmoji(let id):
            Group {
                if let path = model.customEmoji[id] {
                    LocalImageView(path: path, maxPixel: Int(size * 3), contentMode: .fit) { Color.clear }
                } else {
                    Text("✨").font(.system(size: size))
                }
            }
            .frame(width: size + 2, height: size + 2)
            .onAppear { model.ensureCustomEmoji(id) }
        case .paid:
            Text("⭐️").font(.system(size: size))
        }
    }
}

/// "5 Comments" with commenters' avatars — opens the discussion.
struct CommentsBar: View {
    let count: Int
    let commenters: [Commenter]
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                if commenters.isEmpty {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 13))
                        .frame(width: 24)
                } else {
                    HStack(spacing: -8) {
                        ForEach(commenters) { commenter in
                            Avatar(title: commenter.name, seed: commenter.id, size: 24, imagePath: commenter.avatarPath)
                                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        }
                    }
                }
                Text(count == 0 ? "Leave a comment" : "\(count.formatted()) \(count == 1 ? "Comment" : "Comments")")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 7)
            .padding(.horizontal, 2)
            .background(isHovered ? Theme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open comments")
    }
}

/// An official sponsored message, shown after the channel's last post, as
/// Telegram's API terms (3.3) require. Marked viewed only once fully visible.
struct SponsoredBubble: View {
    let model: AppModel
    let item: SponsoredItem

    @State private var showsInfo = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.isRecommended ? "Recommended" : "Sponsored")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Button {
                        showsInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("About this ad")
                    .popover(isPresented: $showsInfo) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sponsored message").font(.headline)
                            Text("Telegram shows minimal, non-targeted ads in large public channels. Telegram Premium subscribers don't see them.")
                            if !item.sponsorInfo.isEmpty { Text(item.sponsorInfo).foregroundStyle(.secondary) }
                            if !item.additionalInfo.isEmpty { Text(item.additionalInfo).foregroundStyle(.secondary) }
                        }
                        .font(.system(size: 12.5))
                        .frame(width: 280, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                    }
                }

                if !item.title.isEmpty {
                    Text(item.title).font(.system(size: 13.5, weight: .semibold))
                }
                Text(FormattedText.attributed(item.text, entities: item.entities, baseSize: 13.5))
                    .font(.system(size: 13.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .onScrollVisibilityChange(threshold: 0.99) { visible in
                        if visible { model.sponsoredBecameVisible(item) }
                    }

                if !item.buttonText.isEmpty {
                    Button {
                        model.openSponsored(item)
                    } label: {
                        Text(item.buttonText)
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: 440, alignment: .leading)
            .background(Theme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 60)
        }
        .padding(.top, 12)
    }
}

/// Wraps children onto new lines, for reaction pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
