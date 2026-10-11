//  Create a new group or channel: name, optional description and photo-less
//  start, then pick members (for groups) and open it.

import SwiftUI
import NodogramDomain
import NodogramUI

enum NewChatKind: String, Identifiable { case group, channel; var id: String { rawValue } }

struct NewChatSheet: View {
    let model: AppModel
    let kind: NewChatKind

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var about = ""
    @State private var selected: Set<ChatID> = []
    @State private var query = ""
    @State private var creating = false

    private var isChannel: Bool { kind == .channel }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isChannel ? "New Channel" : "New Group").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            Form {
                Section {
                    TextField(isChannel ? "Channel name" : "Group name", text: $title)
                    TextField("Description (optional)", text: $about, axis: .vertical).lineLimit(1...3)
                }
                Section(isChannel ? "Add subscribers" : "Add members") {
                    TextField("Search your chats", text: $query).textFieldStyle(.roundedBorder)
                    List(candidates, id: \.id, selection: Binding(get: { selected }, set: { selected = $0 })) { chat in
                        HStack(spacing: 8) {
                            Image(systemName: selected.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(chat.id) ? Theme.accent : .secondary)
                            Avatar(title: chat.title, seed: chat.id.rawValue, size: 26, imagePath: chat.avatarPath, thumbnail: chat.avatarThumbnail)
                            Text(chat.title).lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if selected.contains(chat.id) { selected.remove(chat.id) } else { selected.insert(chat.id) } }
                    }
                    .frame(height: 220)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("\(selected.count) selected").foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
                Button(creating ? "Creating…" : "Create") { create() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || creating)
            }
            .padding(14)
        }
        .frame(width: 440, height: 560)
    }

    private var candidates: [Chat] {
        let q = query.lowercased()
        return model.chatsByID.values
            .filter { chat in
                if case .privateChat = chat.kind { return q.isEmpty || chat.title.lowercased().contains(q) }
                return false
            }
            .sorted { $0.order > $1.order }
            .prefix(200).map { $0 }
    }

    private func create() {
        creating = true
        let members = Array(selected).compactMap { id -> UserID? in
            if case .privateChat(let user) = model.chatsByID[id]?.kind { return user }
            return nil
        }
        model.createChat(title: title.trimmingCharacters(in: .whitespaces),
                         description: about.trimmingCharacters(in: .whitespaces),
                         isChannel: isChannel, members: members, asSupergroup: true)
        dismiss()
    }
}
