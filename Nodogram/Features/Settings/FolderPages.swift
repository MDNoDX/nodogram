//  Chat folders, edited through Telegram so they match the phone, and the
//  sidebar arrangement, which is this Mac's own.

import SwiftUI
import NodogramDomain
import NodogramUI

// MARK: - Folder list

struct FoldersPage: View {
    let model: AppModel

    @State private var recommended: [RecommendedFolder] = []
    @State private var pendingDelete: ChatFolderSummary?

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "folder.fill", tint: SettingsPage.folders.tint,
                             text: "Create folders for different groups of chats and switch between them quickly. Folders sync with Telegram on your phone.")
            }
            Section {
                HStack {
                    Label("All Chats", systemImage: "bubble.left.and.bubble.right")
                    Spacer()
                    Text("Always first").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }
                ForEach(model.folders) { folder in
                    folderRow(folder)
                }
                .onMove { model.moveFolders(from: $0, to: $1) }
                Button {
                    model.settingsPage = .folderEditor(nil)
                } label: {
                    Label("Create New Folder", systemImage: "plus.circle.fill")
                }
                .disabled(model.folders.count >= 10)
            } header: { Text("Folders") } footer: {
                SettingsNote("Drag to reorder. Right-click a folder to edit, hide or delete it. Telegram allows 10 folders, or 30 with Premium.")
            }

            if !recommended.isEmpty {
                Section("Recommended") {
                    ForEach(recommended) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.draft.title).font(.system(size: 13, weight: .medium))
                                Text(item.description).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") {
                                Task {
                                    if await model.saveFolder(id: nil, item.draft) {
                                        recommended.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section {
                Button("Customize Sidebar…") { model.settingsPage = .sidebar }
            } footer: {
                SettingsNote("Choose which folders and sections appear in the sidebar, and in what order.")
            }
        }
        .task { recommended = await model.recommendedFolders() }
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Folder", role: .destructive) {
                if let folder = pendingDelete { model.deleteFolder(folder.id) }
            }
        } message: { Text("The chats stay; only the folder is removed, on all your devices.") }
    }

    private func folderRow(_ folder: ChatFolderSummary) -> some View {
        let hidden = model.isHidden("folder:\(folder.id)")
        let count = model.chatsByID.values.filter { $0.folderOrders[folder.id] != nil }.count
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("Drag to reorder")
            Image(systemName: FolderIcon.symbol(for: folder.iconName)).foregroundStyle(Theme.accent).frame(width: 20)
            Text(folder.title.isEmpty ? "Folder" : folder.title)
            if hidden {
                Text("Hidden").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            Text(count > 0 ? "\(count) chats" : "").font(.system(size: 11.5)).foregroundStyle(.secondary)
            Button { model.setHidden("folder:\(folder.id)", !hidden) } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(hidden ? "Show in sidebar" : "Hide from sidebar")
            Button { model.settingsPage = .folderEditor(folder.id) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .help("Edit folder")
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Folder…") { model.settingsPage = .folderEditor(folder.id) }
            Button(hidden ? "Show in Sidebar" : "Hide from Sidebar") { model.setHidden("folder:\(folder.id)", !hidden) }
            Divider()
            Button("Delete Folder…", role: .destructive) { pendingDelete = folder }
        }
    }
}

// MARK: - Folder editor

struct FolderEditorPage: View {
    let model: AppModel
    let folderID: Int?

    @State private var draft = ChatFolderDraft()
    @State private var loaded = false
    @State private var isSaving = false
    @State private var picking: PickerTarget?

    enum PickerTarget: Identifiable { case include, exclude; var id: Self { self } }

    private static let colors: [Color] = [.red, .orange, .purple, .green, .cyan, .blue, .pink]

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(FolderIcon.all, id: \.name) { icon in
                            Button { draft.iconName = icon.name } label: { Label(icon.name, systemImage: icon.symbol) }
                        }
                    } label: {
                        Image(systemName: FolderIcon.symbol(for: draft.iconName))
                            .font(.system(size: 20))
                            .frame(width: 40, height: 40)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Folder icon")
                    TextField("Folder name", text: $draft.title, prompt: Text("Folder name"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15))
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 10) {
                    Text("Colour").foregroundStyle(.secondary)
                    Button { draft.colorID = -1 } label: {
                        Image(systemName: "nosign").frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Theme.accent, lineWidth: draft.colorID == -1 ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    ForEach(Self.colors.indices, id: \.self) { index in
                        Button { draft.colorID = index } label: {
                            Circle().fill(Self.colors[index]).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(.primary.opacity(0.5), lineWidth: draft.colorID == index ? 2 : 0).padding(-3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: { Text("Name") } footer: {
                SettingsNote("Tip: a single emoji as the name shows as the folder's icon in the sidebar.")
            }

            Section {
                Toggle(isOn: $draft.includeContacts) { Label("Contacts", systemImage: "person.crop.circle") }
                Toggle(isOn: $draft.includeNonContacts) { Label("Non-Contacts", systemImage: "person.crop.circle.badge.questionmark") }
                Toggle(isOn: $draft.includeGroups) { Label("Groups", systemImage: "person.2") }
                Toggle(isOn: $draft.includeChannels) { Label("Channels", systemImage: "megaphone") }
                Toggle(isOn: $draft.includeBots) { Label("Bots", systemImage: "cpu") }
                chatList(draft.includedChatIDs) { id in draft.includedChatIDs.removeAll { $0 == id } }
                Button { picking = .include } label: { Label("Add Chats…", systemImage: "plus") }
            } header: { Text("Included chats") } footer: {
                SettingsNote("Choose chat types and individual chats to show in this folder.")
            }

            Section {
                Toggle(isOn: $draft.excludeMuted) { Label("Muted", systemImage: "bell.slash") }
                Toggle(isOn: $draft.excludeRead) { Label("Read", systemImage: "checkmark.message") }
                Toggle(isOn: $draft.excludeArchived) { Label("Archived", systemImage: "archivebox") }
                chatList(draft.excludedChatIDs) { id in draft.excludedChatIDs.removeAll { $0 == id } }
                Button { picking = .exclude } label: { Label("Exclude Chats…", systemImage: "minus") }
            } header: { Text("Excluded chats") }

            Section {
                HStack {
                    if folderID != nil {
                        Button("Delete Folder", role: .destructive) {
                            if let folderID { model.deleteFolder(folderID) }
                            model.settingsPage = .folders
                        }
                    }
                    Spacer()
                    Button("Cancel") { model.settingsPage = .folders }
                    Button(isSaving ? "Saving…" : (folderID == nil ? "Create" : "Save")) { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty || !draft.includesAnything)
                }
                if !draft.includesAnything {
                    SettingsNote("Include at least one chat type or chat.")
                }
            }
        }
        .task {
            guard !loaded else { return }
            if let folderID, let existing = await model.folderDraft(folderID) { draft = existing }
            loaded = true
        }
        .sheet(item: $picking) { target in
            ChatPickerSheet(model: model, title: target == .include ? "Add Chats" : "Exclude Chats",
                            selected: Set(target == .include ? draft.includedChatIDs : draft.excludedChatIDs)) { chosen in
                if target == .include { draft.includedChatIDs = Array(chosen) } else { draft.excludedChatIDs = Array(chosen) }
            }
        }
    }

    @ViewBuilder
    private func chatList(_ ids: [ChatID], remove: @escaping (ChatID) -> Void) -> some View {
        ForEach(ids, id: \.self) { id in
            HStack(spacing: 8) {
                let chat = model.chatsByID[id]
                Avatar(title: chat?.title ?? "Chat", seed: id.rawValue, size: 22,
                       imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                Text(chat?.title ?? model.chatTitle(id)).lineLimit(1)
                Spacer()
                Button { remove(id) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        isSaving = true
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        Task {
            if await model.saveFolder(id: folderID, draft) { model.settingsPage = .folders }
            isSaving = false
        }
    }
}

/// Pick chats from the loaded chat list, with search.
struct ChatPickerSheet: View {
    let model: AppModel
    let title: String
    @State var selected: Set<ChatID>
    let onDone: (Set<ChatID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(selected.count) selected").foregroundStyle(.secondary).font(.system(size: 12))
            }
            .padding(14)
            TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 14)
            List {
                ForEach(chats) { chat in
                    HStack(spacing: 10) {
                        Image(systemName: selected.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(chat.id) ? Theme.accent : .secondary)
                        Avatar(title: chat.title, seed: chat.id.rawValue, size: 28,
                               imagePath: chat.avatarPath, thumbnail: chat.avatarThumbnail,
                               isSavedMessages: chat.isSavedMessages)
                        Text(chat.isSavedMessages ? "Saved Messages" : chat.title).lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selected.contains(chat.id) { selected.remove(chat.id) } else { selected.insert(chat.id) }
                    }
                }
            }
            .listStyle(.inset)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { onDone(selected); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 420, height: 520)
    }

    private var chats: [Chat] {
        let q = query.lowercased()
        return model.chatsByID.values
            .filter { $0.order != 0 || $0.archiveOrder != 0 || selected.contains($0.id) }
            .filter { q.isEmpty || $0.title.lowercased().contains(q) }
            .sorted { lhs, rhs in
                let l = selected.contains(lhs.id), r = selected.contains(rhs.id)
                return l != r ? l : max(lhs.order, lhs.archiveOrder) > max(rhs.order, rhs.archiveOrder)
            }
    }
}

// MARK: - Sidebar arrangement

struct SidebarPage: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "sidebar.left", tint: SettingsPage.sidebar.tint,
                             text: "Choose what the sidebar shows. Hidden sections stay one ⌘K away.")
            }
            if !model.folders.isEmpty {
                Section("Telegram folders") {
                    ForEach(model.folders) { folder in
                        Toggle(isOn: Binding(get: { !model.isHidden("folder:\(folder.id)") },
                                             set: { model.setHidden("folder:\(folder.id)", !$0) })) {
                            Label(folder.title, systemImage: FolderIcon.symbol(for: folder.iconName))
                        }
                    }
                    .onMove { model.moveFolders(from: $0, to: $1) }
                }
            }
            Section {
                ForEach(model.sidebarPrefs.order, id: \.self) { key in
                    if let destination = SidebarDestination(rawValue: key), destination != .settings {
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Toggle(isOn: Binding(get: { !model.isHidden(key) }, set: { model.setHidden(key, !$0) })) {
                                Label(destination.title, systemImage: destination.icon)
                            }
                            .disabled(destination == .allChats)
                        }
                    }
                }
                .onMove { model.moveDestinations(from: $0, to: $1) }
            } header: { Text("Sections") } footer: {
                SettingsNote("Drag to reorder. All Chats is always shown.")
            }
            Section {
                Button("Restore Defaults") { model.resetSidebar() }
            }
        }
    }
}
