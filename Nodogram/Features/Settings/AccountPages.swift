//  Settings pages backed by Telegram: profile, privacy, sessions and
//  notification defaults. Changes sync to the user's other devices.

import SwiftUI
import NodogramDomain
import NodogramUI

// MARK: - Profile

struct ProfilePage: View {
    let model: AppModel

    @State private var original: ProfileInfo?
    @State private var edited: ProfileInfo?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let edited {
                    header(edited)
                    card {
                        field("First name (required)", text: binding(\.firstName))
                        Divider()
                        field("Last name (optional)", text: binding(\.lastName))
                    }
                    caption("Your name as everyone sees it.")
                    card {
                        TextField("", text: binding(\.bio), prompt: Text("Bio"), axis: .vertical)
                            .textFieldStyle(.plain).font(.system(size: 13.5)).lineLimit(1...4)
                        HStack {
                            Spacer()
                            Text("\(70 - edited.bio.count)").font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(edited.bio.count > 70 ? Theme.failure : .secondary)
                        }
                    }
                    caption("Any details such as age, occupation or city. Example: 23 y.o. designer from Tashkent.")
                    card {
                        HStack(spacing: 2) {
                            Text("@").foregroundStyle(.secondary)
                            TextField("", text: binding(\.username), prompt: Text("username")).textFieldStyle(.plain)
                        }
                        .font(.system(size: 13.5))
                        if !edited.username.isEmpty {
                            Divider()
                            copyRow("t.me/\(edited.username)", copy: "https://t.me/\(edited.username)", accent: true)
                        }
                    }
                    caption("People can find you by this name and message you without your number. 5–32 characters: a–z, 0–9, underscores.")
                    card {
                        copyRow(SettingsListView.formatPhone(edited.phoneNumber), copy: "+" + edited.phoneNumber, label: "mobile")
                        Divider()
                        copyRow(String(edited.userID.rawValue), copy: String(edited.userID.rawValue), label: "your ID")
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.failure)
                            .font(.system(size: 12))
                    }
                    HStack {
                        Spacer()
                        Button("Revert") { self.edited = original; error = nil }
                            .disabled(edited == original || isSaving)
                        Button(isSaving ? "Saving…" : "Save") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .buttonStyle(.borderedProminent)
                            .disabled(edited == original || isSaving || edited.bio.count > 70
                                      || edited.firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    ProgressView().controlSize(.small).padding(40)
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .task {
            original = await model.loadProfile()
            edited = original
        }
    }

    private func header(_ p: ProfileInfo) -> some View {
        VStack(spacing: 8) {
            let chat = model.chatsByID[ChatID(p.userID.rawValue)]
            Avatar(title: p.displayName, seed: p.userID.rawValue, size: 104,
                   imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                .overlay(alignment: .bottomTrailing) {
                    Button(action: choosePhoto) {
                        Image(systemName: "camera.fill").font(.system(size: 12)).foregroundStyle(.white)
                            .frame(width: 30, height: 30).background(Theme.accent, in: Circle())
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .help("Set New Photo")
                }
            HStack(spacing: 5) {
                Text(p.displayName).font(.system(size: 20, weight: .semibold))
                if p.isPremium { Image(systemName: "star.fill").foregroundStyle(.purple) }
            }
            Text("online").font(.system(size: 12.5)).foregroundStyle(Theme.accent)
            Button("Set New Photo…", action: choosePhoto).buttonStyle(.link).font(.system(size: 12.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, -8)
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt)).textFieldStyle(.plain).font(.system(size: 13.5))
    }

    private func copyRow(_ value: String, copy: String, label: String? = nil, accent: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 13.5)).foregroundStyle(accent ? Theme.accent : .primary)
                if let label { Text(label).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copy, forType: .string)
                model.showToast("Copied")
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy")
        }
    }

    private func binding(_ path: WritableKeyPath<ProfileInfo, String>) -> Binding<String> {
        Binding(get: { edited?[keyPath: path] ?? "" }, set: { edited?[keyPath: path] = $0 })
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Set Photo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            error = await model.setProfilePhoto(path: url.path)
            if error == nil { model.showToast("Profile photo updated") }
        }
    }

    private func save() {
        guard let original, let edited else { return }
        isSaving = true
        Task {
            error = await model.saveProfile(old: original, new: edited)
            if error == nil {
                self.original = edited
                model.showToast("Profile saved")
            }
            isSaving = false
        }
    }
}

// MARK: - Privacy

struct PrivacyPage: View {
    let model: AppModel

    @State private var rules: [PrivacyKey: PrivacyRule] = [:]
    @State private var error: String?

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "lock.fill", tint: SettingsPage.privacy.tint,
                             text: "Choose who can see your details and reach you. Changes apply on all your devices.")
            }
            Section("Privacy") {
                ForEach(PrivacyKey.allCases) { key in
                    row(key)
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.failure) }
            }
            Section {
                Toggle("Lock Nodogram with Touch ID", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: AppLockSettings.enabledKey) },
                    set: { UserDefaults.standard.set($0, forKey: AppLockSettings.enabledKey) }))
                Picker("Lock after being away", selection: Binding(
                    get: { AppLockSettings.afterMinutes },
                    set: { UserDefaults.standard.set($0, forKey: AppLockSettings.afterKey) })) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("1 hour").tag(60)
                    Text("Only at launch and sleep").tag(0)
                }
                Button("Lock Now") { model.lockNow() }
            } header: { Text("App lock") } footer: {
                SettingsNote("Chats stay hidden until you unlock with Touch ID or your Mac's password. Nodogram keeps receiving messages while locked.")
            }
            Section {
                Toggle("Hide message previews in notifications", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "notifications.privacyMode") },
                    set: { UserDefaults.standard.set($0, forKey: "notifications.privacyMode") }))
            } header: { Text("On this Mac") } footer: {
                SettingsNote("Banners then say only that a message arrived — useful when sharing your screen.")
            }
        }
        .task {
            for key in PrivacyKey.allCases {
                if let rule = await model.privacyRule(key) { rules[key] = rule }
            }
        }
    }

    @ViewBuilder
    private func row(_ key: PrivacyKey) -> some View {
        HStack {
            Label(key.title, systemImage: key.symbol)
            Spacer()
            if let rule = rules[key] {
                if rule.exceptionCount > 0 {
                    Text("+\(rule.exceptionCount)").font(.system(size: 11)).foregroundStyle(.secondary)
                        .help("Exceptions set in Telegram are kept")
                }
                Picker("", selection: Binding(get: { rule.audience }, set: { newValue in
                    var updated = rule
                    updated.audience = newValue
                    rules[key] = updated
                    Task {
                        error = await model.setPrivacy(key, updated)
                        if error != nil, let fresh = await model.privacyRule(key) { rules[key] = fresh }
                    }
                })) {
                    ForEach(PrivacyRule.Audience.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

// MARK: - Sessions

struct SessionsPage: View {
    let model: AppModel

    @State private var sessions: [SessionInfo] = []
    @State private var loaded = false
    @State private var confirmAll = false
    @State private var pending: SessionInfo?
    @State private var error: String?

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "laptopcomputer.and.iphone", tint: SettingsPage.sessions.tint,
                             text: "Every device signed in to your account. End any session you don't recognise.")
            }
            if let current = sessions.first(where: \.isCurrent) {
                Section("This device") { sessionRow(current) }
            }
            let others = sessions.filter { !$0.isCurrent }
            if !others.isEmpty {
                Section {
                    Button(role: .destructive) { confirmAll = true } label: {
                        Label("Terminate All Other Sessions", systemImage: "hand.raised.fill")
                    }
                }
                Section("Active sessions") {
                    ForEach(others) { session in
                        sessionRow(session)
                            .contextMenu {
                                Button("Terminate Session", role: .destructive) { pending = session }
                            }
                    }
                }
            } else if loaded {
                Section { SettingsNote("No other devices are signed in.") }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.failure) }
            }
        }
        .task { await reload() }
        .confirmationDialog("Terminate all other sessions?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Terminate", role: .destructive) {
                Task { error = await model.terminateOtherSessions(); await reload() }
            }
        } message: { Text("Every other device will be signed out of your account.") }
        .confirmationDialog("Terminate this session?", isPresented: Binding(get: { pending != nil },
                                                                            set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible) {
            Button("Terminate", role: .destructive) {
                guard let session = pending else { return }
                Task { error = await model.terminate(session); await reload() }
            }
        } message: { Text(pending.map { "\($0.applicationName) on \($0.deviceModel)" } ?? "") }
    }

    private func reload() async {
        sessions = await model.loadSessions()
        loaded = true
    }

    private func sessionRow(_ s: SessionInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.symbol)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background((s.isOfficial ? Color.blue : Color.orange).gradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.applicationName) \(s.applicationVersion)").font(.system(size: 13, weight: .semibold))
                Text([s.deviceModel, s.platform, s.systemVersion].filter { !$0.isEmpty }.joined(separator: ", "))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text([s.location, s.ipAddress].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(s.isCurrent ? "online" : RelativeTimeFormatter.short(s.lastActive))
                .font(.system(size: 11.5))
                .foregroundStyle(s.isCurrent ? Theme.accent : .secondary)
            if !s.isCurrent {
                Button { pending = s } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Terminate")
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Notifications

struct NotificationsPage: View {
    let model: AppModel

    @AppStorage(AppModel.notificationsEnabledKey) private var enabled = true
    @AppStorage("notifications.privacyMode") private var privacyMode = false
    @AppStorage(AppModel.dockBadgeKey) private var dockBadge = true
    @State private var scopes: [ScopeNotifications.Scope: ScopeNotifications] = [:]

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show notifications on this Mac", isOn: $enabled)
                Toggle("Hide message text and sender", isOn: $privacyMode).disabled(!enabled)
                Toggle("Unread count on the Dock icon", isOn: $dockBadge)
            } header: { Text("This Mac") }

            Section {
                ForEach(ScopeNotifications.Scope.allCases) { scope in
                    HStack {
                        Label(scope.title, systemImage: scope.symbol)
                        Spacer()
                        if let value = scopes[scope] {
                            Toggle("Preview", isOn: Binding(get: { value.showPreview }, set: { update(scope, preview: $0) }))
                                .toggleStyle(.checkbox)
                                .disabled(value.isMuted)
                            Toggle("", isOn: Binding(get: { !value.isMuted }, set: { update(scope, muted: !$0) }))
                                .toggleStyle(.switch)
                                .labelsHidden()
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            } header: { Text("Message notifications") } footer: {
                SettingsNote("Defaults for each kind of chat, synced with Telegram. A chat's own mute setting overrides them.")
            }

            Section {
                Button("Open macOS Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } footer: { SettingsNote("Banner style, sounds and Focus are controlled by macOS.") }
        }
        .task {
            for scope in ScopeNotifications.Scope.allCases {
                if let value = await model.scopeNotifications(scope) { scopes[scope] = value }
            }
        }
    }

    private func update(_ scope: ScopeNotifications.Scope, muted: Bool? = nil, preview: Bool? = nil) {
        guard var value = scopes[scope] else { return }
        if let muted { value.isMuted = muted }
        if let preview { value.showPreview = preview }
        scopes[scope] = value
        Task { await model.setScopeNotifications(scope, value) }
    }
}
