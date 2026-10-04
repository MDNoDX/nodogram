//  ⌘K: jump to any chat, section, or message by typing.

import SwiftUI
import NodogramDomain
import NodogramUI

struct CommandPalette: View {
    let model: AppModel

    @State private var query = ""
    @State private var messages: [Message] = []
    @State private var selection = 0
    @FocusState private var focused: Bool

    private enum Item: Identifiable {
        case chat(Chat)
        case destination(SidebarDestination)
        case message(Message)

        var id: String {
            switch self {
            case .chat(let c): return "c\(c.id.rawValue)"
            case .destination(let d): return "d\(d.rawValue)"
            case .message(let m): return "m\(m.uniqueKey)"
            }
        }
    }

    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let chats: [Chat]
        if q.isEmpty {
            chats = model.recentChatIDs.prefix(8).compactMap { model.chatsByID[$0] }
        } else {
            chats = model.chatsByID.values
                .filter { $0.title.lowercased().contains(q) }
                .sorted { lhs, rhs in
                    let l = lhs.title.lowercased().hasPrefix(q), r = rhs.title.lowercased().hasPrefix(q)
                    return l != r ? l : lhs.order > rhs.order
                }
                .prefix(8).map { $0 }
        }
        let destinations = q.isEmpty ? [] : SidebarDestination.allCases.filter { $0.title.lowercased().contains(q) }
        return chats.map(Item.chat) + destinations.map(Item.destination) + messages.prefix(12).map(Item.message)
    }

    var body: some View {
        let list = items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Chats, sections and messages", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { activate(list) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(list.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                    .onKeyPress(.escape) { model.isPaletteVisible = false; return .handled }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                            row(item)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == selection ? Theme.accent.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                                .onTapGesture { selection = index; activate(list) }
                                .id(index)
                        }
                        if list.isEmpty {
                            Text(query.isEmpty ? "Type to search." : "No results.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .padding(14)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }
            .frame(maxHeight: 380)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .task(id: query) {
            messages = []
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let found = await model.searchMessagesEverywhere(query)
            if !Task.isCancelled { messages = found }
        }
    }

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item {
        case .chat(let chat):
            HStack(spacing: 10) {
                Avatar(title: chat.title, seed: chat.id.rawValue, size: 26, imagePath: chat.avatarPath,
                       thumbnail: chat.avatarThumbnail, isSavedMessages: chat.isSavedMessages)
                Text(chat.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Spacer()
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        case .destination(let destination):
            Label(destination.title, systemImage: destination.icon).font(.system(size: 13.5))
        case .message(let message):
            VStack(alignment: .leading, spacing: 1) {
                Text(model.chatTitle(message.chatID)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(message.text.isEmpty ? (message.attachmentLabel ?? "") : message.text)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func activate(_ list: [Item]) {
        guard list.indices.contains(selection) else { return }
        model.isPaletteVisible = false
        switch list[selection] {
        case .chat(let chat):
            if model.selectedDestination != .allChats, !model.destinationIsChatList { model.selectedDestination = .allChats }
            model.select(chat.id)
        case .destination(let destination):
            model.selectedDestination = destination
        case .message(let message):
            model.jump(to: message.id, in: message.chatID)
        }
    }
}
