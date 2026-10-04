//  Back and forward through where the user has been: sections, folders,
//  chats and settings pages. ⌘[ ⌘], the toolbar arrows, the mouse's side
//  buttons and a two-finger swipe all use this.

import Foundation
import NodogramDomain

public struct NavigationState: Equatable, Sendable {
    var destination: SidebarDestination
    var folderID: Int?
    var chatID: ChatID?
    var settingsPage: SettingsPage
}

extension AppModel {

    var currentNavigation: NavigationState {
        NavigationState(destination: selectedDestination, folderID: selectedFolderID,
                        chatID: selectedChatID, settingsPage: settingsPage)
    }

    /// Records a step. Settings pages count only while Settings is open, and
    /// consecutive identical states collapse.
    func noteNavigation() {
        guard !isReplayingNavigation else { return }
        let now = currentNavigation
        defer { lastNavigation = now }
        guard let last = lastNavigation, last != now else { return }
        if last.destination != .settings, now.destination != .settings, last.settingsPage != now.settingsPage,
           last.chatID == now.chatID, last.destination == now.destination { return }
        navBack.append(last)
        if navBack.count > 60 { navBack.removeFirst(navBack.count - 60) }
        navForward.removeAll()
    }

    public var canGoBack: Bool { !navBack.isEmpty }
    public var canGoForward: Bool { !navForward.isEmpty }

    public func goBack() {
        guard let target = navBack.popLast() else { return }
        navForward.append(currentNavigation)
        replay(target)
    }

    public func goForward() {
        guard let target = navForward.popLast() else { return }
        navBack.append(currentNavigation)
        replay(target)
    }

    private func replay(_ state: NavigationState) {
        isReplayingNavigation = true
        defer {
            isReplayingNavigation = false
            lastNavigation = state
        }
        if let folder = state.folderID {
            selectFolder(folder)
        } else if selectedDestination != state.destination || selectedFolderID != nil {
            selectedDestination = state.destination
        }
        settingsPage = state.settingsPage
        if selectedChatID != state.chatID { select(state.chatID) }
    }
}
