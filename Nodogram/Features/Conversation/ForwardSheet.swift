//  Choosing where to forward, with Telegram's two options: whether to credit
//  the original sender, and whether to keep media captions.

import SwiftUI
import NodogramDomain
import NodogramUI

struct ForwardSheet: View {
    let model: AppModel
    let request: ForwardRequest

    @State private var query = ""
    @State private var targets: [ChatID] = []
    @State private var showSender = true
    @State private var showCaptions = true
    @Environment(\.dismiss) private var dismiss

    private var chats: [Chat] {
        let all = model.chatsByID.values.filter { $0.order != 0 && $0.canPost }.sorted { $0.order > $1.order }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(request.messageIDs.count == 1 ? "Forward Message" : "Forward \(request.messageIDs.count) Messages")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding([.horizontal, .top], 16)

            TextField("Search chats", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(16)

            List(chats) { chat in
                Button {
                    if let index = targets.firstIndex(of: chat.id) { targets.remove(at: index) } else { targets.append(chat.id) }
                } label: {
                    HStack(spacing: 10) {
                        Avatar(title: chat.title, seed: chat.id.rawValue, size: 32, imagePath: chat.avatarPath,
                               thumbnail: chat.avatarThumbnail, isSavedMessages: chat.isSavedMessages)
                        Text(chat.title).lineLimit(1)
                        Spacer()
                        Image(systemName: targets.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(targets.contains(chat.id) ? Theme.accent : .secondary)
                            .font(.system(size: 17))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { model.ensureAvatar(for: chat.id) }
            }
            .listStyle(.inset)
            .frame(minHeight: 300)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show sender's name", isOn: $showSender)
                    .help("Off sends the message as if you wrote it, without “Forwarded from”.")
                if request.hasCaptions {
                    Toggle("Show captions", isOn: $showCaptions)
                        .disabled(showSender)
                        .help("Captions can be removed only when the sender's name is hidden.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack {
                Button("Cancel") { model.forwardRequest = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(targets.count > 1 ? "Forward to \(targets.count) Chats" : "Forward") {
                    model.completeForward(request, to: targets,
                                          options: ForwardOptions(showSender: showSender, showCaptions: showSender || showCaptions))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(targets.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420, height: 560)
        .onChange(of: showSender) { _, show in if show { showCaptions = true } }
    }
}

/// The translation of a message, in a popover beside it.
struct TranslationPopover: View {
    let model: AppModel
    let message: Message

    @State private var result: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Translation", systemImage: "translate")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            if let result {
                Text(result)
                    .font(.system(size: 13.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copy") { model.copyText(of: [Message(id: message.id, chatID: message.chatID, text: result, date: message.date)]) }
                    .buttonStyle(.borderless)
            } else if failed {
                Text("Translation isn't available for this message right now.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: 340, alignment: .leading)
        .padding(14)
        .task {
            if let translated = await model.translate(message) { result = translated } else { failed = true }
        }
    }
}
