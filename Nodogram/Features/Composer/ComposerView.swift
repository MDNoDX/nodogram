//  Message composer.
//
//  ⌘↩ sends; ↩ inserts a newline. In a messenger used for real work an
//  accidental send is worse than an extra keystroke (brief §21).

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ComposerView: View {
    private let chatID: ChatID
    @Binding private var text: String
    private let draftIndicatorVisible: Bool
    private let mode: AppModel.ComposerMode
    private let onCancelMode: () -> Void
    private let onAttach: ([URL]) -> Void
    private let onSend: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        chatID: ChatID,
        text: Binding<String>,
        draftIndicatorVisible: Bool,
        mode: AppModel.ComposerMode = .normal,
        onCancelMode: @escaping () -> Void = {},
        onAttach: @escaping ([URL]) -> Void = { _ in },
        onSend: @escaping () -> Void
    ) {
        self.chatID = chatID
        self._text = text
        self.draftIndicatorVisible = draftIndicatorVisible
        self.mode = mode
        self.onCancelMode = onCancelMode
        self.onAttach = onAttach
        self.onSend = onSend
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            if let banner = modeBanner {
                HStack(spacing: 10) {
                    Image(systemName: banner.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(banner.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                        Text(banner.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button(action: onCancelMode) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel (esc)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 9)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button(action: pickFiles) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 32)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: .command)
                .help("Attach files (⌘O) — or drop them onto the chat")

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(L10n.messagePlaceholder)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .padding(.top, 1)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 13.5))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .focused($isFocused)
                        .frame(minHeight: 20, maxHeight: 140)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? Theme.accent.opacity(0.55) : Color.secondary.opacity(0.25), lineWidth: 1)
                )

                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(canSend ? Theme.accent : Color.secondary.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("\(L10n.send) (⌘↩)")
                .accessibilityLabel(L10n.send)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack {
                // Quiet and non-blocking: the brief forbids interrupting typing.
                Text(draftIndicatorVisible ? L10n.draftSaved : " ")
                    .animation(.easeInOut(duration: 0.2), value: draftIndicatorVisible)
                Spacer()
                Text("⌘↩ to send")
                    .opacity(canSend ? 1 : 0)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 18)
            .padding(.bottom, 7)
        }
        .background(.bar)
        .onAppear { isFocused = true }
        .onChange(of: chatID) { _, _ in isFocused = true }
        .onChange(of: mode) { _, _ in isFocused = true }
    }

    private var modeBanner: (icon: String, title: String, text: String)? {
        switch mode {
        case .normal:
            return nil
        case .replying(let message):
            return ("arrowshape.turn.up.left", "Reply to \(message.isOutgoing ? "yourself" : message.senderName)",
                    message.text.isEmpty ? (message.attachmentLabel ?? "Message") : message.text)
        case .editing(let message):
            return ("pencil", "Edit message", message.text)
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose photos, videos or files to send"
        panel.prompt = "Send"
        if panel.runModal() == .OK { onAttach(panel.urls) }
    }
}
