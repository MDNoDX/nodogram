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
    private let onSend: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        chatID: ChatID,
        text: Binding<String>,
        draftIndicatorVisible: Bool,
        onSend: @escaping () -> Void
    ) {
        self.chatID = chatID
        self._text = text
        self.draftIndicatorVisible = draftIndicatorVisible
        self.onSend = onSend
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 10) {
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
    }
}
