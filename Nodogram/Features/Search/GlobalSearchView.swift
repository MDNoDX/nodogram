//  The global-search overlay: a search box, result tabs, and (when empty)
//  recent chats and recommendations — in the shape of Telegram's search.

import SwiftUI
import NodogramDomain
import NodogramUI

struct GlobalSearchView: View {
    let model: AppModel
    @Bindable var state: GlobalSearchState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search chats, channels, people and messages", text: $state.query)
                    .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                    .onSubmit { model.runGlobalSearch(state.query) }
                    .onChange(of: state.query) { _, q in model.runGlobalSearch(q) }
                if state.searching { ProgressView().controlSize(.small) }
                Button { model.closeGlobalSearch() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            if state.query.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyState
            } else {
                Picker("", selection: $state.tab) {
                    ForEach(GlobalSearchState.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().padding(10)
                Divider()
                results
            }
        }
        .frame(width: 620, height: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !state.recent.isEmpty {
                    header("Recent")
                    ForEach(state.recent, id: \.self) { chatRow($0) }
                }
                if !state.recommended.isEmpty {
                    header("Recommended")
                    ForEach(state.recommended, id: \.self) { chatRow($0) }
                }
                if state.recent.isEmpty && state.recommended.isEmpty {
                    Text("Type to search all of Telegram — your chats, public channels, people, bots and messages.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let showChats = state.tab == .all || state.tab == .chats
                let showChannels = state.tab == .all || state.tab == .channels
                let showBots = state.tab == .all || state.tab == .bots
                let showMessages = state.tab == .all || state.tab == .media

                if showChats, !state.localChats.isEmpty {
                    header("Your chats")
                    ForEach(state.localChats, id: \.self) { chatRow($0) }
                }
                if showChats, !state.globalChats.isEmpty {
                    header("People and groups")
                    ForEach(state.globalChats, id: \.self) { chatRow($0) }
                }
                if showChannels, !state.channels.isEmpty {
                    header("Channels")
                    ForEach(state.channels, id: \.self) { chatRow($0) }
                }
                if showBots, !state.bots.isEmpty {
                    header("Bots")
                    ForEach(state.bots, id: \.self) { chatRow($0) }
                }
                if showMessages, !state.messages.isEmpty {
                    header("Messages")
                    ForEach(state.messages, id: \.uniqueKey) { messageRow($0) }
                }
                if !state.searching && everythingEmpty {
                    Text("Nothing found for “\(state.query)”.").font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var everythingEmpty: Bool {
        state.localChats.isEmpty && state.globalChats.isEmpty && state.channels.isEmpty
            && state.bots.isEmpty && state.messages.isEmpty
    }

    private func header(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
    }

    private func chatRow(_ id: ChatID) -> some View {
        let chat = model.chatsByID[id]
        return Button { model.openSearchResult(id) } label: {
            HStack(spacing: 10) {
                Avatar(title: chat?.title ?? "…", seed: id.rawValue, size: 38,
                       imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail, isSavedMessages: chat?.isSavedMessages ?? false)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(chat?.title ?? "Loading…").font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                        if chat?.isVerified == true { Image(systemName: "checkmark.seal.fill").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                    }
                    Text(subtitle(chat)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ chat: Chat?) -> String {
        guard let chat else { return "" }
        switch chat.kind {
        case .channel: return chat.memberCount > 0 ? "\(chat.memberCount.formatted()) subscribers" : "Channel"
        case .basicGroup, .supergroup: return chat.memberCount > 0 ? "\(chat.memberCount.formatted()) members" : "Group"
        case .privateChat where chat.isBot: return "Bot"
        case .privateChat, .secret: return PresenceFormatter.describe(chat.presence, now: Date()) ?? "User"
        }
    }

    private func messageRow(_ message: Message) -> some View {
        Button { model.closeGlobalSearch(); model.jump(to: message.id, in: message.chatID) } label: {
            HStack(spacing: 10) {
                let chat = model.chatsByID[message.chatID]
                Avatar(title: model.chatTitle(message.chatID), seed: message.chatID.rawValue, size: 34,
                       imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(model.chatTitle(message.chatID)).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text(RelativeTimeFormatter.short(message.date)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Text(message.text.isEmpty ? (message.attachmentLabel ?? "") : message.text)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
