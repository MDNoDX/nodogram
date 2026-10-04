//  The comments of a channel post, in a panel beside the conversation —
//  Telegram's discussion thread, without leaving the channel.

import SwiftUI
import NodogramDomain
import NodogramUI

struct CommentsPanel: View {
    let model: AppModel
    let state: CommentsState

    @FocusState private var composerFocused: Bool

    private var post: Message? {
        model.messages.first { $0.id == state.postMessageID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Comments").font(.system(size: 14, weight: .semibold))
                    if let count = post?.commentCount {
                        Text("\(count.formatted()) \(count == 1 ? "comment" : "comments")")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: { model.closeComments() }) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close (esc)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let post {
                            postPreview(post).padding(.bottom, 6)
                        }
                        if state.isLoading {
                            ProgressView().controlSize(.small).padding(30)
                        } else if let error = state.error {
                            EmptyStateView(icon: "exclamationmark.bubble", title: "Comments unavailable", message: error)
                        } else if state.messages.isEmpty {
                            EmptyStateView(icon: "bubble.left", title: "No comments yet",
                                           message: "Be the first to comment on this post.")
                        } else {
                            let rows = TimelineRow.build(from: state.messages, groupChat: true)
                            ForEach(rows) { row in
                                switch row.kind {
                                case .day(let date): DaySeparator(date: date)
                                case .service(let message): ServiceLine(message: message)
                                case .message(let message, let position):
                                    MessageRow(model: model, message: message, position: position,
                                               showsSender: true, showsReadLabel: false, showsReceipts: false)
                                        .id(message.id)
                                        .contextMenu {
                                            Button("Reply") { model.replyInComments(to: message); composerFocused = true }
                                            Button("Copy Text") { model.copyText(of: [message]) }
                                        }
                                case .album(let items, let position):
                                    MessageRow(model: model, message: items.first { !$0.text.isEmpty } ?? items[0],
                                               position: position, showsSender: true, showsReadLabel: false,
                                               showsReceipts: false, album: items)
                                        .id(items[0].id)
                                }
                            }
                        }
                        Color.clear.frame(height: 6).id("comments-bottom")
                    }
                    .padding(.horizontal, 12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: state.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("comments-bottom", anchor: .bottom) }
                }
            }

            composer
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func postPreview(_ post: Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.selectedChat?.title ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(post.text.isEmpty ? (post.attachmentLabel ?? "Post") : post.text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 10)
    }

    private var canSend: Bool {
        !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.discussionChatID != nil
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            if let reply = state.replyTo {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Reply to \(reply.senderName)").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
                        Text(reply.text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.replyInComments(to: nil) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Comment…", text: Binding(get: { state.draft }, set: { model.setCommentDraft($0) }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...6)
                    .focused($composerFocused)
                    .onSubmit(model.sendComment)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))
                Button(action: { model.sendComment() }) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(canSend ? Theme.accent : Color.secondary.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(10)
        }
        .background(.bar)
    }
}
