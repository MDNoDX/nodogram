//  The global-search overlay, shaped like Telegram's: a search field, a Saved
//  shortcut and Recent list when empty, and result tabs (Chats, Channels,
//  Apps, Media, Links, Files) with your own chats shown apart from public ones.

import SwiftUI
import NodogramDomain
import NodogramUI

struct GlobalSearchView: View {
    let model: AppModel
    @Bindable var state: GlobalSearchState
    @FocusState private var focused: Bool

    private var isEmpty: Bool { state.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if isEmpty {
                emptyState
            } else {
                tabs
                Divider()
                results
            }
        }
        .frame(width: 640, height: 660)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $state.query)
                .textFieldStyle(.plain).font(.system(size: 15)).focused($focused)
                .onChange(of: state.query) { _, q in model.runGlobalSearch(q) }
            if state.searching { ProgressView().controlSize(.small) }
            if !isEmpty {
                Button { state.query = ""; model.runGlobalSearch("") } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button { model.closeGlobalSearch() } label: { Text("Cancel").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(GlobalSearchState.Tab.allCases, id: \.self) { tab in
                    Button {
                        state.tab = tab
                        model.loadContentTab()
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: state.tab == tab ? .semibold : .regular))
                            .foregroundStyle(state.tab == tab ? Theme.accent : .secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(alignment: .bottom) {
                                if state.tab == tab { Rectangle().fill(Theme.accent).frame(height: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                savedChip
                if !state.recent.isEmpty {
                    HStack {
                        sectionHeader("Recent")
                        Spacer()
                        Button("clear") { model.clearRecentSearches() }
                            .font(.system(size: 11)).foregroundStyle(.secondary).buttonStyle(.plain)
                            .padding(.trailing, 14).padding(.top, 10)
                    }
                    ForEach(state.recent, id: \.self) { chatRow($0) }
                }
                if !state.recommended.isEmpty {
                    sectionHeader("Recommended")
                    ForEach(state.recommended, id: \.self) { chatRow($0) }
                }
                if state.recent.isEmpty && state.recommended.isEmpty {
                    Text("Search all of Telegram — your chats, channels, people, bots and messages.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var savedChip: some View {
        Button { model.openSavedMessages() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.accent.gradient).frame(width: 38, height: 38)
                    Image(systemName: "bookmark.fill").font(.system(size: 16)).foregroundStyle(.white)
                }
                Text("Saved Messages").font(.system(size: 13.5, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                switch state.tab {
                case .chats:
                    if !state.localChats.isEmpty {
                        sectionHeader("Your chats")
                        ForEach(state.localChats, id: \.self) { chatRow($0) }
                    }
                    if !state.globalPeople.isEmpty {
                        sectionHeader("Global search")
                        ForEach(state.globalPeople, id: \.self) { chatRow($0) }
                    }
                    if !state.messages.isEmpty {
                        sectionHeader("Messages")
                        ForEach(state.messages, id: \.uniqueKey) { messageRow($0) }
                    }
                case .channels:
                    ForEach(state.channels, id: \.self) { chatRow($0) }
                case .apps:
                    ForEach(state.bots, id: \.self) { chatRow($0) }
                case .media, .links, .files:
                    ForEach(state.content, id: \.uniqueKey) { messageRow($0) }
                }
                if !state.searching && currentEmpty {
                    Text("Nothing found for “\(state.query)”.").font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var currentEmpty: Bool {
        switch state.tab {
        case .chats: return state.localChats.isEmpty && state.globalPeople.isEmpty && state.messages.isEmpty
        case .channels: return state.channels.isEmpty
        case .apps: return state.bots.isEmpty
        case .media, .links, .files: return state.content.isEmpty
        }
    }

    private func sectionHeader(_ title: String) -> some View {
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
