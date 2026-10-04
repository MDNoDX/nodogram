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
        SettingsForm {
            if let edited {
                Section {
                    HStack(spacing: 14) {
                        let chat = model.chatsByID[ChatID(edited.userID.rawValue)]
                        Avatar(title: edited.displayName, seed: edited.userID.rawValue, size: 72,
                               imagePath: chat?.avatarPath, thumbnail: chat?.avatarThumbnail)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(edited.displayName).font(.system(size: 18, weight: .semibold))
                            Text(SettingsListView.formatPhone(edited.phoneNumber)).foregroundStyle(.secondary)
                            Text("online").font(.system(size: 12)).foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Name") {
                    TextField("First name", text: binding(\.firstName))
                    TextField("Last name", text: binding(\.lastName))
                }
                Section {
                    TextField("Bio", text: binding(\.bio), axis: .vertical)
                        .lineLimit(2...4)
                    HStack {
                        Spacer()
                        Text("\(70 - edited.bio.count)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(edited.bio.count > 70 ? Theme.failure : .secondary)
                    }
                } header: { Text("Bio") } footer: {
                    SettingsNote("A few words about yourself. Anyone who opens your profile can see it.")
                }
                Section {
                    TextField("Username", text: binding(\.username))
                } header: { Text("Username") } footer: {
                    SettingsNote("People can find you by this name and write to you without knowing your number. 5–32 characters: a–z, 0–9 and underscores.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.failure) }
                }
                Section {
                    HStack {
                        Spacer()
                        Button("Revert") { self.edited = original; error = nil }
                            .disabled(edited == original || isSaving)
                        Button(isSaving ? "Saving…" : "Save") { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .buttonStyle(.borderedProminent)
                            .disabled(edited == original || isSaving || edited.bio.count > 70)
                    }
                }
            } else {
                Section { HStack { Spacer(); ProgressView().controlSize(.small); Spacer() } }
            }
        }
        .task {
            original = await model.loadProfile()
            edited = original
        }
    }

    private func binding(_ path: WritableKeyPath<ProfileInfo, String>) -> Binding<String> {
        Binding(get: { edited?[keyPath: path] ?? "" }, set: { edited?[keyPath: path] = $0 })
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
