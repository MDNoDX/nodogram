//  Bars that sit above or below the timeline: search, selection, and the
//  read-only bar that replaces the composer where the user cannot post.

import SwiftUI
import AppKit
import NodogramDomain
import NodogramUI

/// ⌘F: search this chat; ↩ / ⇧↩ or the arrows step through results.
struct ConversationSearchBar: View {
    let model: AppModel
    let state: ConversationSearchState

    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search this chat", text: $query)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit { model.runConversationSearch(query) }
            if state.isSearching {
                ProgressView().controlSize(.small)
            } else if !state.query.isEmpty {
                Text(state.results.isEmpty ? "No results" : "\(state.index + 1) of \(state.results.count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button { model.stepConversationSearch(1) } label: { Image(systemName: "chevron.up") }
                .disabled(state.results.count < 2).help("Older result")
            Button { model.stepConversationSearch(-1) } label: { Image(systemName: "chevron.down") }
                .disabled(state.results.count < 2).help("Newer result")
            Button("Done") { model.endConversationSearch() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { query = state.query; focused = true }
    }
}

/// Replaces the composer while messages are selected.
struct SelectionBar: View {
    let model: AppModel
    @State private var confirmingDelete = false

    var body: some View {
        let selected = model.selectedMessages
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 18) {
                Button("Cancel") { model.endSelection() }
                    .keyboardShortcut(.cancelAction)
                Text("\(selected.count) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.copyText(of: selected) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(selected.isEmpty || selected.contains { !$0.canBeSaved })
                Button { model.forward(selected) } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                    .disabled(selected.isEmpty || selected.contains { !$0.canBeSaved })
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selected.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(.bar)
        .confirmationDialog("Delete \(selected.count) messages?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete for Everyone", role: .destructive) { model.delete(selected, forEveryone: true) }
            Button("Delete for Me", role: .destructive) { model.delete(selected, forEveryone: false) }
        } message: {
            Text("Messages you aren't allowed to delete for everyone are deleted only for you.")
        }
    }
}

/// Channels the user reads but cannot post in show Mute / Unmute here, as
/// Telegram does; other read-only chats say why.
struct ReadOnlyBar: View {
    let model: AppModel
    let chat: Chat

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                if case .channel = chat.kind {
                    Button {
                        model.setMuted(!chat.isMuted, chat: chat.id)
                    } label: {
                        Label(chat.isMuted ? "Unmute" : "Mute",
                              systemImage: chat.isMuted ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 13.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                } else {
                    Text(chat.isServiceAccount ? "This is Telegram's service account."
                         : "You can't send messages in this chat.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
            }
        }
        .background(.bar)
    }
}

/// Keeps protected chats out of screenshots and screen recordings: macOS
/// leaves windows whose sharing type is `.none` out of captures. Restored when
/// the chat is left.
struct ScreenshotProtection: NSViewRepresentable {
    let isProtected: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.sharingType = isProtected ? .none : .readOnly
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        view.window?.sharingType = .readOnly
    }
}
