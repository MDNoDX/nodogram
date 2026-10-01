//  Message composer.
//
//  Keyboard behaviour matters more here than anywhere else in the app:
//  ⌘↵ sends, ↵ inserts a newline. That split is deliberate — in a messenger
//  used for real work, an accidental ↵ send is worse than an extra keystroke.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct ComposerView: View {
    @Binding private var text: String
    private let draftIndicatorVisible: Bool
    private let onSend: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        draftIndicatorVisible: Bool,
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.draftIndicatorVisible = draftIndicatorVisible
        self.onSend = onSend
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // "Draft saved" is quiet and non-blocking: the brief forbids
            // interrupting typing with UI (brief §23).
            if draftIndicatorVisible {
                Text(L10n.draftSaved)
                    .font(Theme.Typography.timestamp)
                    .foregroundStyle(Theme.tertiaryText)
                    .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    // Attachment picking arrives with the media phase.
                } label: {
                    Image(systemName: "paperclip")
                }
                .buttonStyle(.borderless)
                .help("Attach a file")
                .disabled(true)

                TextEditor(text: $text)
                    .font(Theme.Typography.messageBody)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 22, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($isFocused)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(L10n.messagePlaceholder)
                                .font(Theme.Typography.messageBody)
                                .foregroundStyle(Theme.tertiaryText)
                                .allowsHitTesting(false)
                        }
                    }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 19))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canSend ? Theme.accent : Theme.tertiaryText)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("\(L10n.send) (⌘↵)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .onAppear { isFocused = true }
    }
}
