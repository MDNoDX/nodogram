//  Stories: the strip above the chat list and the viewer.

import Foundation
import NodogramDomain
import NodogramTelegram

extension AppModel {

    /// Owners in Telegram's order, unseen first, then the rest.
    public var orderedStoryOwners: [StoryOwner] {
        storyOwners.values
            .filter { chatsByID[$0.chatID] != nil }
            .sorted { lhs, rhs in
                if lhs.hasUnread != rhs.hasUnread { return lhs.hasUnread }
                return lhs.order > rhs.order
            }
    }

    public func openStories(from owner: ChatID) {
        let owners = orderedStoryOwners.map(\.chatID)
        guard let index = owners.firstIndex(of: owner) else { return }
        // Start at the first unseen story, as Telegram does.
        let stories = storyOwners[owner]
        let firstUnseen = stories?.storyIDs.firstIndex { $0 > (stories?.maxReadStoryID ?? 0) } ?? 0
        storyViewer = StoryViewerState(owners: owners, ownerIndex: index, storyIndex: firstUnseen)
    }

    public func closeStories() {
        storyViewer = nil
    }

    public func story(_ id: Int, of owner: ChatID) async -> StoryItem? {
        await gateway?.story(id, of: owner)
    }

    public func storyOpened(_ id: Int, of owner: ChatID) {
        guard let gateway else { return }
        Task { await gateway.markStoryOpened(id, of: owner) }
    }

    public func storyClosed(_ id: Int, of owner: ChatID) {
        guard let gateway else { return }
        Task { await gateway.markStoryClosed(id, of: owner) }
    }
}
