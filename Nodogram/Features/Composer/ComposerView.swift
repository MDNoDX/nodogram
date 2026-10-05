//  Message composer.
//
//  ↩ sends and ⇧↩ starts a new line, or ⌘↩ sends (Settings → General).
//  Right-click the send button to send without sound or schedule.

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
    private let onSendWithOptions: (Bool, Date?) -> Void
    private let isSavedMessages: Bool
    private let assistantReady: Bool
    private let onSuggest: () async throws -> [ReplySuggestion]

    @State private var scheduling = false
    @State private var suggesting = false
    @State private var suggestions: [ReplySuggestion] = []
    @State private var showSuggestions = false
    @State private var suggestError: String?
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @FocusState private var isFocused: Bool
    @AppStorage("composer.sendWithEnter") private var sendWithEnter = true

    public init(
        chatID: ChatID,
        text: Binding<String>,
        draftIndicatorVisible: Bool,
        mode: AppModel.ComposerMode = .normal,
        onCancelMode: @escaping () -> Void = {},
        onAttach: @escaping ([URL]) -> Void = { _ in },
        isSavedMessages: Bool = false,
        onSend: @escaping () -> Void,
        onSendWithOptions: @escaping (Bool, Date?) -> Void = { _, _ in },
        assistantReady: Bool = false,
        onSuggest: @escaping () async throws -> [ReplySuggestion] = { [] }
    ) {
        self.onSendWithOptions = onSendWithOptions
        self.isSavedMessages = isSavedMessages
        self.assistantReady = assistantReady
        self.onSuggest = onSuggest
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
                        // Telegram's default: ↩ sends, ⇧↩ starts a new line.
                        .onKeyPress(.return, phases: .down) { press in
                            guard sendWithEnter, !press.modifiers.contains(.shift),
                                  !press.modifiers.contains(.option) else { return .ignored }
                            if canSend { onSend() }
                            return .handled
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? Theme.accent.opacity(0.55) : Color.secondary.opacity(0.25), lineWidth: 1)
                )

                if assistantReady {
                    Button { suggest() } label: {
                        Image(systemName: suggesting ? "ellipsis" : "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(Theme.accent)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(suggesting)
                    .help("Suggest replies")
                    .popover(isPresented: $showSuggestions, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reply ideas").font(.headline)
                            if let suggestError {
                                Text(suggestError).font(.system(size: 12)).foregroundStyle(Theme.failure)
                            }
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    text = suggestion.text
                                    showSuggestions = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.tone.uppercased()).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.accent)
                                        Text(suggestion.text).font(.system(size: 13)).foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(8)
                                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Tap to put it in the box. Edit before sending.").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        }
                        .padding(14).frame(width: 320)
                    }
                }

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
                .contextMenu {
                    Button { onSendWithOptions(true, nil) } label: { Label("Send Without Sound", systemImage: "bell.slash") }
                    Button { scheduling = true } label: {
                        Label(isSavedMessages ? "Set a Reminder…" : "Schedule Message…", systemImage: "calendar.badge.clock")
                    }
                }
                .popover(isPresented: $scheduling, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isSavedMessages ? "Remind me" : "Send on").font(.headline)
                        DatePicker("", selection: $scheduleDate, in: Date().addingTimeInterval(60)...,
                                   displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical).labelsHidden()
                        HStack {
                            ForEach([("In 1 hour", 3600.0), ("Tonight 21:00", -1), ("Tomorrow 9:00", -2)], id: \.0) { item in
                                Button(item.0) { scheduleDate = Self.preset(item.1) }.controlSize(.small)
                            }
                        }
                        HStack {
                            Spacer()
                            Button("Cancel") { scheduling = false }
                            Button(isSavedMessages ? "Set Reminder" : "Schedule") {
                                scheduling = false
                                onSendWithOptions(false, scheduleDate)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSend)
                        }
                    }
                    .padding(14)
                    .frame(width: 300)
                }
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
                Text(sendWithEnter ? "↩ to send · ⇧↩ new line" : "⌘↩ to send")
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

    static func preset(_ code: Double) -> Date {
        let calendar = Calendar.current
        if code > 0 { return Date().addingTimeInterval(code) }
        let base = code == -1 ? Date() : calendar.date(byAdding: .day, value: 1, to: Date())!
        let hour = code == -1 ? 21 : 9
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? Date()
        return date > Date() ? date : date.addingTimeInterval(86_400)
    }

    private func suggest() {
        suggesting = true; suggestError = nil
        Task {
            do {
                suggestions = try await onSuggest()
                showSuggestions = !suggestions.isEmpty
                if suggestions.isEmpty { suggestError = "No ideas this time." }
            } catch {
                suggestError = (error as? AIError)?.errorDescription ?? error.localizedDescription
                showSuggestions = true
            }
            suggesting = false
        }
    }
}
