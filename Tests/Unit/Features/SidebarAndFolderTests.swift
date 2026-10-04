//  Sidebar arrangement defaults and folder icon mapping.

import Foundation
import Testing
@testable import NodogramFeatures
import NodogramDomain

@Suite("Sidebar and folders")
struct SidebarAndFolderTests {

    @Test("Content sections start hidden; chats and trackers start visible")
    func defaults() {
        let hidden = SidebarPrefs.defaultHidden
        for key in ["media", "files", "links", "voiceMessages"] { #expect(hidden.contains(key)) }
        for key in ["allChats", "localArchive", "typingLog", "storyViews", "myActivity"] { #expect(!hidden.contains(key)) }
    }

    @Test("Every rail destination is in the default order exactly once")
    func defaultOrder() {
        let keys = SidebarDestination.railCases.map(\.rawValue)
        #expect(Set(keys).count == keys.count)
        #expect(!keys.contains("settings"))
    }

    @Test("Folder icons map to symbols, unknown names to a folder")
    func icons() {
        #expect(FolderIcon.symbol(for: "Work") == "briefcase")
        #expect(FolderIcon.symbol(for: "Nonexistent") == "folder")
    }

    @Test("A folder must include something")
    func includes() {
        var draft = ChatFolderDraft(title: "Work")
        #expect(!draft.includesAnything)
        draft.includeGroups = true
        #expect(draft.includesAnything)
        draft = ChatFolderDraft(title: "One", includedChatIDs: [ChatID(5)])
        #expect(draft.includesAnything)
    }

    @Test("Typing log round-trips through JSON")
    func typingCodable() throws {
        let event = TypingEvent(id: UUID(), chatID: 1, userID: 2, name: "Ali", chatTitle: "Ali", isGroup: false,
                                activity: "typing", startedAt: Date(timeIntervalSince1970: 1000),
                                lastSeenAt: Date(timeIntervalSince1970: 1012), endedAt: Date(timeIntervalSince1970: 1012),
                                outcome: .abandoned, messagePreview: nil)
        let data = try JSONEncoder().encode([event])
        let back = try JSONDecoder().decode([TypingEvent].self, from: data)
        #expect(back == [event])
        #expect(back[0].duration == 12)
    }
}
