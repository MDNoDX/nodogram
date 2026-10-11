//  Telegram-style global search: a Saved shortcut and Recent list when empty;
//  when searching, tabs for Chats, Channels, Apps (bots), and message content
//  (Media, Links, Files) — your own chats listed apart from public results.

import Foundation
import SwiftUI
import NodogramDomain
import NodogramTelegram
import NodogramUI

@MainActor
@Observable
public final class GlobalSearchState {
    public enum Tab: String, CaseIterable, Sendable {
        case chats = "Chats", channels = "Channels", apps = "Apps", media = "Media", links = "Links", files = "Files"
    }
    public var query = ""
    public var tab: Tab = .chats
    // Chats tab
    public var localChats: [ChatID] = []
    public var globalPeople: [ChatID] = []
    // Other tabs
    public var channels: [ChatID] = []
    public var bots: [ChatID] = []
    public var messages: [Message] = []
    public var content: [Message] = []
    // Empty state
    public var recent: [ChatID] = []
    public var recommended: [ChatID] = []
    public var searching = false
    var token = 0
    var contentToken = 0
}

extension AppModel {

    public func openGlobalSearch(initial: String = "") {
        let state = GlobalSearchState()
        state.query = initial
        globalSearch = state
        Task { [weak self] in
            guard let self, let gateway = self.gateway else { return }
            async let recent = gateway.recentlyFoundChats()
            async let recommended = gateway.recommendedChats()
            async let topPeople = gateway.topChats(.people)
            state.recent = await recent
            var rec = await recommended
            if rec.isEmpty { rec = await topPeople }
            state.recommended = rec
            for id in state.recent + state.recommended { self.ensureAvatar(for: id) }
        }
        if !initial.isEmpty { runGlobalSearch(initial) }
    }

    public func closeGlobalSearch() { globalSearch = nil }

    public func clearRecentSearches() {
        globalSearch?.recent = []
        Task { await gateway?.clearRecentChats() }
    }

    public func runGlobalSearch(_ query: String) {
        guard let state = globalSearch, let gateway else { return }
        state.query = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.token += 1
        let token = state.token
        guard !trimmed.isEmpty else {
            state.localChats = []; state.globalPeople = []; state.channels = []
            state.bots = []; state.messages = []; state.content = []
            state.searching = false
            return
        }
        state.searching = true
        Task { [weak self] in
            guard let self else { return }
            let local = await gateway.searchLocalChats(trimmed)
            if state.token == token { state.localChats = local; for id in local { self.ensureAvatar(for: id) } }

            async let globalChatsTask = gateway.searchGlobalChats(trimmed)
            async let messagesTask = gateway.searchGlobalMessages(trimmed)
            let global = await globalChatsTask
            let msgs = await messagesTask
            guard state.token == token else { return }

            var channels: [ChatID] = [], bots: [ChatID] = [], people: [ChatID] = []
            for id in global {
                var chat = self.chatsByID[id]
                if chat == nil { chat = await gateway.resolveChat(id) }
                guard let chat else { people.append(id); continue }
                self.chatsByID[chat.id] = chat
                switch chat.kind {
                case .channel: channels.append(id)
                case .privateChat where chat.isBot: bots.append(id)
                default: people.append(id)
                }
            }
            guard state.token == token else { return }
            state.globalPeople = people
            state.channels = channels
            state.bots = bots
            state.messages = msgs.messages
            state.searching = false
            for id in global { self.ensureAvatar(for: id) }
        }
        loadContentTab()
    }

    /// Loads the active content tab (Media/Links/Files) on demand.
    public func loadContentTab() {
        guard let state = globalSearch, let gateway else { return }
        let filter: TelegramGateway.MediaFilter
        switch state.tab {
        case .media: filter = .photosAndVideos
        case .links: filter = .links
        case .files: filter = .files
        default: return
        }
        let trimmed = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state.content = []; return }
        state.contentToken += 1
        let token = state.contentToken
        Task { [weak self] in
            let found = await gateway.searchGlobalContent(filter, query: trimmed)
            guard self != nil, state.contentToken == token else { return }
            state.content = found
        }
    }

    public func openSearchResult(_ id: ChatID) {
        if chatsByID[id] == nil {
            Task { [weak self] in
                if let chat = await self?.gateway?.resolveChat(id) { self?.chatsByID[chat.id] = chat }
                self?.selectedDestination = .allChats
                self?.select(id)
            }
        } else {
            selectedDestination = .allChats
            select(id)
        }
        closeGlobalSearch()
    }

    public func openSavedMessages() {
        guard let me = myUserID else { return }
        selectedDestination = .allChats
        select(ChatID(me.rawValue))
        closeGlobalSearch()
    }
}
