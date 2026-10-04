//  Telegram chat folders, and the user's own sidebar arrangement.

import Foundation
import NodogramDomain
import NodogramTelegram

/// What the sidebar shows, and in what order. Built-in sections are ordered
/// and hidden locally; Telegram folders keep Telegram's order (so they match
/// the phone) and can be hidden here without deleting them.
public struct SidebarPrefs: Codable, Equatable, Sendable {
    public var order: [String]
    public var hidden: Set<String>

    static let key = "sidebar.prefs.v1"

    /// Content sections start hidden: they are reachable from ⌘K and the
    /// chat header, and most people do not need them in the rail.
    static let defaultHidden: Set<String> = ["media", "files", "links", "voiceMessages", "recentlyViewed"]

    static func load() -> SidebarPrefs {
        if let data = UserDefaults.standard.data(forKey: key),
           var prefs = try? JSONDecoder().decode(SidebarPrefs.self, from: data) {
            // Sections added in a later version appear at the end.
            for d in SidebarDestination.railCases where !prefs.order.contains(d.rawValue) { prefs.order.append(d.rawValue) }
            return prefs
        }
        return SidebarPrefs(order: SidebarDestination.railCases.map(\.rawValue), hidden: defaultHidden)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

extension SidebarDestination {
    /// Everything that can sit in the rail (Settings is pinned to the bottom).
    public static var railCases: [SidebarDestination] { allCases.filter { $0 != .settings } }
}

extension AppModel {

    // MARK: - Folder selection

    public func selectFolder(_ id: Int) {
        selectedDestination = .allChats
        selectedFolderID = id
        loadMoreChats(in: .folder(id))
    }

    func chats(inFolder id: Int) -> [Chat] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return chatsByID.values
            .filter { $0.folderOrders[id] != nil }
            .filter { query.isEmpty || $0.title.lowercased().contains(query) }
            .sorted { ($0.folderOrders[id] ?? 0) > ($1.folderOrders[id] ?? 0) }
    }

    public func unreadCount(inFolder id: Int) -> Int {
        chatsByID.values.filter { $0.folderOrders[id] != nil && $0.appearsUnread && !$0.isMuted }.count
    }

    /// Folders containing a chat, for the tags shown in the chat list.
    public func folderTitles(for chat: Chat) -> [String] {
        folders.filter { chat.folderOrders[$0.id] != nil }.map(\.title)
    }

    // MARK: - Sidebar arrangement

    public var visibleRailDestinations: [SidebarDestination] {
        sidebarPrefs.order.compactMap(SidebarDestination.init(rawValue:))
            .filter { $0 != .settings && !sidebarPrefs.hidden.contains($0.rawValue) }
    }

    public var visibleFolders: [ChatFolderSummary] {
        folders.filter { !sidebarPrefs.hidden.contains("folder:\($0.id)") }
    }

    public func isHidden(_ key: String) -> Bool { sidebarPrefs.hidden.contains(key) }

    public func setHidden(_ key: String, _ hidden: Bool) {
        if hidden { sidebarPrefs.hidden.insert(key) } else { sidebarPrefs.hidden.remove(key) }
        sidebarPrefs.save()
        if hidden, key == selectedDestination.rawValue { selectedDestination = .allChats }
        if hidden, let id = selectedFolderID, key == "folder:\(id)" { selectedDestination = .allChats }
    }

    public func moveDestinations(from source: IndexSet, to destination: Int) {
        sidebarPrefs.order.move(fromOffsets: source, toOffset: destination)
        sidebarPrefs.save()
    }

    public func resetSidebar() {
        sidebarPrefs = SidebarPrefs(order: SidebarDestination.railCases.map(\.rawValue),
                                    hidden: SidebarPrefs.defaultHidden)
        sidebarPrefs.save()
    }

    // MARK: - Folder editing (through Telegram)

    public func moveFolders(from source: IndexSet, to destination: Int) {
        var ids = folders.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        folders = ids.compactMap { id in folders.first { $0.id == id } }
        guard let gateway else { return }
        Task { [weak self] in
            do { try await gateway.reorderFolders(ids) }
            catch { self?.showToast("Couldn't reorder folders: \(AppModel.describe(error))") }
        }
    }

    public func folderDraft(_ id: Int) async -> ChatFolderDraft? {
        try? await gateway?.chatFolder(id)
    }

    /// Creates (id nil) or updates a folder. Returns false and shows why on failure.
    @discardableResult
    public func saveFolder(id: Int?, _ draft: ChatFolderDraft) async -> Bool {
        guard let gateway else { return false }
        do {
            if let id { try await gateway.editFolder(id, draft) } else { try await gateway.createFolder(draft) }
            showToast(id == nil ? "Folder created" : "Folder saved")
            return true
        } catch {
            showToast(AppModel.describe(error))
            return false
        }
    }

    public func deleteFolder(_ id: Int) {
        guard let gateway else { return }
        if selectedFolderID == id { selectedDestination = .allChats }
        Task { [weak self] in
            do { try await gateway.deleteFolder(id); self?.showToast("Folder deleted") }
            catch { self?.showToast(AppModel.describe(error)) }
        }
    }

    public func recommendedFolders() async -> [RecommendedFolder] {
        await gateway?.recommendedFolders() ?? []
    }

    /// Adds or removes one chat from a folder, from the chat's context menu.
    public func setChat(_ chatID: ChatID, inFolder folderID: Int, included: Bool) {
        Task { [weak self] in
            guard let self, var draft = await self.folderDraft(folderID) else { return }
            draft.includedChatIDs.removeAll { $0 == chatID }
            draft.excludedChatIDs.removeAll { $0 == chatID }
            draft.pinnedChatIDs.removeAll { $0 == chatID }
            if included { draft.includedChatIDs.append(chatID) } else { draft.excludedChatIDs.append(chatID) }
            await self.saveFolder(id: folderID, draft)
        }
    }
}
