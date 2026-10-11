//  Telegram-style global search: your chats, public chats and channels, people
//  and bots found on Telegram's servers, and messages anywhere — with
//  recommendations when the box is empty.

import Foundation
import SwiftUI
import NodogramDomain
import NodogramUI

@MainActor
@Observable
public final class GlobalSearchState {
    public enum Tab: String, CaseIterable, Sendable { case all = "All", chats = "Chats", channels = "Channels", media = "Media", bots = "Bots" }
    public var query = ""
    public var tab: Tab = .all
    public var localChats: [ChatID] = []
    public var globalChats: [ChatID] = []
    public var channels: [ChatID] = []
    public var bots: [ChatID] = []
    public var messages: [Message] = []
    public var recent: [ChatID] = []
    public var recommended: [ChatID] = []
    public var searching = false
    var token = 0
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

    public func runGlobalSearch(_ query: String) {
        guard let state = globalSearch, let gateway else { return }
        state.query = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        state.token += 1
        let token = state.token
        guard !trimmed.isEmpty else {
            state.localChats = []; state.globalChats = []; state.channels = []; state.bots = []; state.messages = []
            state.searching = false
            return
        }
        state.searching = true
        Task { [weak self] in
            guard let self else { return }
            // Local first (instant), then the server results as they arrive.
            let local = await gateway.searchLocalChats(trimmed)
            if state.token == token { state.localChats = local; for id in local { self.ensureAvatar(for: id) } }

            async let globalChatsTask = gateway.searchGlobalChats(trimmed)
            async let messagesTask = gateway.searchGlobalMessages(trimmed)
            let global = await globalChatsTask
            let msgs = await messagesTask
            guard state.token == token else { return }

            // Split public results by kind so the tabs are meaningful.
            var channels: [ChatID] = [], bots: [ChatID] = [], others: [ChatID] = []
            for id in global {
                var chat = self.chatsByID[id]
                if chat == nil { chat = await gateway.resolveChat(id) }
                guard let chat else { others.append(id); continue }
                self.chatsByID[chat.id] = chat
                switch chat.kind {
                case .channel: channels.append(id)
                case .privateChat where chat.isBot: bots.append(id)
                default: others.append(id)
                }
            }
            guard state.token == token else { return }
            state.globalChats = others
            state.channels = channels
            state.bots = bots
            state.messages = msgs.messages
            state.searching = false
            for id in global { self.ensureAvatar(for: id) }
        }
    }

    /// Opens a search result, loading the chat into the list if it's new.
    public func openSearchResult(_ id: ChatID) {
        if chatsByID[id] == nil {
            Task { [weak self] in
                _ = await self?.gateway?.resolveChat(id)
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
}
