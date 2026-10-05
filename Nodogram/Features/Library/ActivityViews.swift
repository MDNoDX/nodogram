//  Typing log, story viewers, and the user's own footprint (groups, their
//  messages, members of groups they run).

import SwiftUI
import NodogramDomain
import NodogramUI

// MARK: - Typing log

struct TypingLogView: View {
    let model: AppModel

    enum Filter: String, CaseIterable { case all = "All", abandoned = "Didn't send", sent = "Sent" }
    @State private var filter: Filter = .all
    @State private var query = ""

    private var events: [TypingEvent] {
        model.typingLog.filter { event in
            switch filter {
            case .all: break
            case .abandoned: if event.outcome != .abandoned { return false }
            case .sent: if event.outcome != .sent { return false }
            }
            return query.isEmpty || event.name.localizedCaseInsensitiveContains(query)
                || event.chatTitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                TextField("Filter", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 120)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if events.isEmpty {
                EmptyStateView(icon: "ellipsis.bubble", title: "No typing yet",
                               message: model.typingLog.isEmpty
                                   ? "When someone starts typing to you, it is logged here — with whether they actually sent anything."
                                   : "Nothing matches this filter.")
            } else {
                List {
                    ForEach(grouped, id: \.day) { group in
                        Section(DaySeparator.label(for: group.day)) {
                            ForEach(group.events) { TypingRow(model: model, event: $0) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { model.markTypingSeen() }
    }

    private var grouped: [(day: Date, events: [TypingEvent])] {
        let calendar = Calendar.current
        var result: [(day: Date, events: [TypingEvent])] = []
        for event in events {
            let day = calendar.startOfDay(for: event.startedAt)
            if result.last?.day == day { result[result.count - 1].events.append(event) }
            else { result.append((day, [event])) }
        }
        return result
    }
}

private struct TypingRow: View {
    let model: AppModel
    let event: TypingEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            let chat = model.chatsByID[ChatID(event.chatID)]
            Avatar(title: event.name, seed: event.userID, size: 34,
                   imagePath: event.isGroup ? nil : chat?.avatarPath,
                   thumbnail: event.isGroup ? nil : chat?.avatarThumbnail)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if event.isGroup {
                        Text("in \(event.chatTitle)").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(event.startedAt.formatted(.dateTime.hour().minute().second()))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    outcomeBadge
                    Text("\(event.activity) · \(AppModel.durationText(event.duration))")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                if let preview = event.messagePreview, !preview.isEmpty {
                    Text(preview).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.8)).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { openChat() }
        .contextMenu { Button("Open Chat") { openChat() } }
    }

    @ViewBuilder
    private var outcomeBadge: some View {
        switch event.outcome {
        case .pending:
            Label("typing now", systemImage: "ellipsis")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.accent)
        case .sent:
            Label("Sent", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.success)
        case .abandoned:
            Label("Didn't send", systemImage: "xmark.circle.fill")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.warning)
        }
    }

    private func openChat() {
        model.selectedDestination = .allChats
        model.select(ChatID(event.chatID))
    }
}

// MARK: - Story viewers

struct StoryViewsView: View {
    let model: AppModel

    @State private var query = ""
    @State private var refreshing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Set(model.storyViewers.map(\.userID)).count) people")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(model.myStoryIDs.count) live " + (model.myStoryIDs.count == 1 ? "story" : "stories"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Search", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 130)
                Button {
                    refreshing = true
                    Task { await model.refreshStoryViewers(); refreshing = false }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(refreshing).help("Check now")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if model.storyViewers.isEmpty {
                EmptyStateView(icon: "eye.circle", title: "No story views yet",
                               message: "Post a story on your phone. While Nodogram runs, everyone who views it is kept here — even after the story expires.")
            } else {
                List {
                    ForEach(byStory, id: \.storyID) { group in
                        Section {
                            ForEach(group.viewers) { viewer in
                                HStack(spacing: 10) {
                                    let chat = model.chatsByID[ChatID(viewer.userID)]
                                    Avatar(title: viewer.name, seed: viewer.userID, size: 30,
                                           imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(viewer.name).font(.system(size: 13, weight: .medium))
                                        Text(RelativeTimeFormatter.exact(viewer.viewedAt))
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let reaction = viewer.reaction { Text(reaction).font(.system(size: 18)) }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selectedDestination = .allChats
                                    model.select(ChatID(viewer.userID))
                                }
                            }
                        } header: {
                            HStack {
                                Text("Story #\(group.storyID)")
                                if model.myStoryIDs.contains(group.storyID) {
                                    Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 4).background(Theme.accent, in: Capsule())
                                }
                                Spacer()
                                Text("\(group.viewers.count) views")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var byStory: [(storyID: Int, viewers: [StoryViewer])] {
        let filtered = model.storyViewers.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let groups = Dictionary(grouping: filtered, by: \.storyID)
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.viewedAt > $1.viewedAt }) }
    }
}

// MARK: - My activity

struct MyActivityView: View {
    let model: AppModel

    @State private var groups: [GroupSummary] = []
    @State private var query = ""
    @State private var managing: GroupSummary?
    @State private var filter = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                SearchField(text: $query, prompt: "Search groups, channels and people")
                Picker("", selection: $filter) {
                    Text("All").tag(0)
                    Text("Groups").tag(1)
                    Text("Channels").tag(2)
                    Text("I run").tag(3)
                    Text("Left").tag(4)
                    Text("Saved me").tag(5)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if filter == 5 {
                MutualContactsList(model: model, query: query)
            } else if visible.isEmpty {
                EmptyStateView(icon: "person.2", title: "No groups here",
                               message: "Groups and channels you are in appear here once your chat list has loaded.")
            } else {
                List(visible) { group in
                    HStack(spacing: 10) {
                        let chat = model.chatsByID[group.id]
                        Avatar(title: group.title, seed: group.id.rawValue, size: 36,
                               imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                            .onAppear { model.ensureAvatar(for: group.id) }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: group.isChannel ? "megaphone.fill" : "person.2.fill")
                                    .font(.system(size: 9)).foregroundStyle(.secondary)
                                Text(group.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            }
                            HStack(spacing: 6) {
                                roleBadge(group.role)
                                if group.memberCount > 0 {
                                    Text("\(group.memberCount.formatted()) \(group.isChannel ? "subscribers" : "members")")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { managing = group }
                    .contextMenu {
                        Button("Open Chat") { model.selectedDestination = .allChats; model.select(group.id) }
                        Button("Manage…") { managing = group }
                    }
                }
                .listStyle(.inset)
            }
        }
        .task { groups = model.myGroups() }
        .onChange(of: model.chatsByID.count) { _, _ in groups = model.myGroups() }
        .sheet(item: $managing) { group in
            GroupManageSheet(model: model, group: group) { groups = model.myGroups() }
        }
    }

    private var visible: [GroupSummary] {
        groups.filter { group in
            switch filter {
            case 0: if group.role == .left { return false }
            case 1: if group.isChannel || group.role == .left { return false }
            case 2: if !group.isChannel || group.role == .left { return false }
            case 3: if group.role == .member || group.role == .left { return false }
            case 4: if group.role != .left { return false }
            default: break
            }
            return query.isEmpty || group.title.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func roleBadge(_ role: GroupSummary.Role) -> some View {
        switch role {
        case .owner:
            Text("Owner").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(Color.orange, in: Capsule())
        case .admin:
            Text("Admin").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.accent, in: Capsule())
        case .member:
            EmptyView()
        case .left:
            Text("Left").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(Color.gray, in: Capsule())
        }
    }
}

/// People who saved you in their contacts — as far as Telegram reveals it:
/// only those you have saved too ("mutual contacts").
private struct MutualContactsList: View {
    let model: AppModel
    let query: String
    @State private var people: [UserID] = []
    @State private var loaded = false

    var body: some View {
        let visible = people.filter { query.isEmpty || model.chatTitle(ChatID($0.rawValue)).localizedCaseInsensitiveContains(query) }
        Group {
            if !loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(visible, id: \.self) { user in
                            let chat = model.chatsByID[ChatID(user.rawValue)]
                            HStack(spacing: 10) {
                                Avatar(title: chat?.title ?? model.chatTitle(ChatID(user.rawValue)), seed: user.rawValue, size: 32,
                                       imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                                Text(chat?.title ?? model.chatTitle(ChatID(user.rawValue))).font(.system(size: 13))
                                Spacer()
                                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10)).foregroundStyle(Theme.success)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedDestination = .allChats
                                model.select(ChatID(user.rawValue))
                            }
                        }
                    } header: {
                        Text("\(people.count) people have you in their contacts")
                    } footer: {
                        Text("Telegram tells you only about people you have saved too. Nobody — no app or bot — can list strangers who saved your number, or who opened your profile.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
        .task {
            people = await model.mutualContacts()
            loaded = true
        }
    }
}

/// One group or channel: the user's messages there, its members (when the
/// user may remove them), and leaving.
struct GroupManageSheet: View {
    let model: AppModel
    let group: GroupSummary
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var myMessages: [Message] = []
    @State private var myTotal = 0
    @State private var loadingMessages = true
    @State private var deleting: (done: Int, total: Int)?
    @State private var confirmDeleteAll = false
    @State private var confirmLeave = false
    @State private var members: [MemberInfo] = []
    @State private var memberTotal = 0
    @State private var memberQuery = ""
    @State private var selectedMembers: Set<UserID> = []
    @State private var confirmRemove: Bool?   // true = ban, false = remove
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                let chat = model.chatsByID[group.id]
                Avatar(title: group.title, seed: group.id.rawValue, size: 40,
                       imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                VStack(alignment: .leading) {
                    Text(group.title).font(.headline).lineLimit(1)
                    Text(group.isChannel ? "Channel" : "Group").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Chat") { model.selectedDestination = .allChats; model.select(group.id); dismiss() }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Picker("", selection: $tab) {
                Text("My Messages (\(myTotal))").tag(0)
                if group.canRemoveMembers { Text("Members (\(memberTotal))").tag(1) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.failure)
                    .font(.system(size: 12)).padding(.top, 8)
            }

            if tab == 0 { messagesTab } else { membersTab }

            Divider()
            HStack {
                Button("Leave \(group.isChannel ? "Channel" : "Group")…", role: .destructive) { confirmLeave = true }
                    .disabled(group.role == .owner)
                    .help(group.role == .owner ? "Owners must transfer ownership in Telegram first" : "")
                Spacer()
            }
            .padding(14)
        }
        .frame(width: 560, height: 620)
        .task { await loadMessages() }
        .task { if group.canRemoveMembers { await loadMembers() } }
        .confirmationDialog("Delete all \(myTotal) of your messages here?", isPresented: $confirmDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete for Everyone", role: .destructive) { deleteAll() }
        } message: { Text("Your messages are removed from \(group.title) for every member. This can't be undone.") }
        .confirmationDialog("Leave \(group.title)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    error = await model.leave(group.id)
                    if error == nil { onChange(); dismiss() }
                }
            }
        }
        .confirmationDialog(confirmRemove == true ? "Ban \(selectedMembers.count) members?" : "Remove \(selectedMembers.count) members?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible) {
            Button(confirmRemove == true ? "Ban" : "Remove", role: .destructive) { removeSelected(ban: confirmRemove == true) }
        } message: {
            Text(confirmRemove == true
                 ? "They are removed and cannot rejoin until unbanned."
                 : "They are removed and can rejoin through an invite link.")
        }
    }

    private var messagesTab: some View {
        VStack(spacing: 8) {
            HStack {
                if let deleting {
                    ProgressView(value: Double(deleting.done), total: Double(max(deleting.total, 1)))
                    Text("\(deleting.done)/\(deleting.total)").font(.system(size: 11).monospacedDigit())
                } else {
                    Text(myTotal == 0 ? "You haven't written anything here." : "\(myTotal) messages written by you")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Delete All My Messages…", role: .destructive) { confirmDeleteAll = true }
                        .disabled(myTotal == 0)
                }
            }
            .padding(.horizontal, 14).padding(.top, 10)
            if loadingMessages {
                ProgressView().controlSize(.small).frame(maxHeight: .infinity)
            } else {
                List(myMessages, id: \.uniqueKey) { message in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.text.isEmpty ? (message.attachmentLabel ?? "Message") : message.text)
                            .font(.system(size: 12.5)).lineLimit(3)
                        Text(RelativeTimeFormatter.exact(message.date)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedDestination = .allChats
                        model.jump(to: message.id, in: group.id)
                        dismiss()
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var membersTab: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search members", text: $memberQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await loadMembers() } }
                if !selectedMembers.isEmpty {
                    Button("Remove \(selectedMembers.count)") { confirmRemove = false }
                    Button("Ban", role: .destructive) { confirmRemove = true }
                }
            }
            .padding(.horizontal, 14).padding(.top, 10)
            List(members) { member in
                HStack(spacing: 10) {
                    let removable = member.role == .member || member.role == .restricted
                    Image(systemName: selectedMembers.contains(member.userID) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedMembers.contains(member.userID) ? Theme.accent : .secondary)
                        .opacity(removable ? 1 : 0.2)
                    Avatar(title: member.name, seed: member.userID.rawValue, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(member.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            if member.isBot { Image(systemName: "cpu").font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                        Text([member.username.isEmpty ? nil : "@\(member.username)",
                              member.joinedAt.map { "joined \(RelativeTimeFormatter.short($0))" }]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if member.role == .owner || member.role == .admin {
                        Text(member.role == .owner ? "Owner" : "Admin").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard member.role == .member || member.role == .restricted else { return }
                    if selectedMembers.contains(member.userID) { selectedMembers.remove(member.userID) }
                    else { selectedMembers.insert(member.userID) }
                }
            }
            .listStyle(.inset)
        }
    }

    private func loadMessages() async {
        loadingMessages = true
        let page = await model.myMessages(in: group.id)
        myMessages = page.messages
        myTotal = page.total
        loadingMessages = false
    }

    private func loadMembers() async {
        let result = await model.members(of: group.id, query: memberQuery)
        members = result.members
        memberTotal = result.total
    }

    private func deleteAll() {
        deleting = (0, myTotal)
        Task {
            error = await model.deleteAllMyMessages(in: group.id) { done, total in deleting = (done, total) }
            deleting = nil
            await loadMessages()
        }
    }

    private func removeSelected(ban: Bool) {
        let targets = members.filter { selectedMembers.contains($0.userID) }
        Task {
            for member in targets {
                if let failure = await model.remove(member, from: group.id, ban: ban) { error = failure; break }
            }
            selectedMembers = []
            await loadMembers()
            model.showToast(ban ? "Banned \(targets.count)" : "Removed \(targets.count)")
        }
    }
}
