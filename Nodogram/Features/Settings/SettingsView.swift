//  Settings window (⌘,).

import SwiftUI
import AppKit
import NodogramCore
import NodogramPlatform
import NodogramUI

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560)
        .padding(.vertical, 6)
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @State private var folder = MediaLibrary.folder
    @AppStorage(MediaLibrary.autoSaveKey) private var autoSave = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Save files to") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                            .resizable().frame(width: 18, height: 18)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 240, alignment: .leading)
                        Button("Change…", action: choose)
                    }
                }
                HStack {
                    Button("Show in Finder") { MediaLibrary.openFolder() }
                    if folder != MediaLibrary.defaultFolder {
                        Button("Use Default") {
                            MediaLibrary.resetFolder()
                            folder = MediaLibrary.folder
                        }
                    }
                }
                Toggle("Save downloaded files to this folder automatically", isOn: $autoSave)
            } header: {
                Text("Downloads")
            } footer: {
                Text("“Save” and “Show in Finder” copy files here. Media in chats that don't allow saving is never copied.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Telegram cache") {
                    Button("Show in Finder") {
                        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        NSWorkspace.shared.open(support.appendingPathComponent("Nodogram/accounts/default/files"))
                    }
                }
            } footer: {
                Text("Telegram's own working copies. Managed automatically — use “Save” to keep a file.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Choose"
        panel.message = "Choose where Nodogram saves downloaded files"
        if panel.runModal() == .OK, let url = panel.url {
            MediaLibrary.setFolder(url)
            folder = url
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @AppStorage(AppModel.keepDeletedKey) private var keepDeleted = false
    @AppStorage(AppModel.deletedRetentionKey) private var retentionDays = 365
    @State private var stats: MessageArchive.Statistics?
    @State private var confirmingErase = false
    @State private var confirmingForever = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep messages that others delete", isOn: $keepDeleted)

                Picker("Keep deleted messages for", selection: Binding(
                    get: { retentionDays },
                    set: { newValue in
                        if newValue == 0 { confirmingForever = true } else { retentionDays = newValue }
                    })) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
                .disabled(!keepDeleted)

                if let stats {
                    LabeledContent("Kept on this Mac", value: "\(stats.deleted) deleted messages")
                }

                Button("Erase Archive…", role: .destructive) { confirmingErase = true }
            } header: {
                Text("Deleted messages")
            } footer: {
                Text("""
                    Off by default. Self-destructing, auto-deleting and copy-protected messages are never \
                    kept, as Telegram's API terms require. Messages preserved here are stored locally on \
                    this Mac, encrypted with a key in your Keychain. Anyone with access to this Mac account may be able to read them. This does \
                    not undo deletion on Telegram, and cannot recover messages this Mac never received — \
                    for example ones sent and deleted while Nodogram was closed.
                    """)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
        .onChange(of: keepDeleted) { _, _ in Task { await refresh() } }
        .confirmationDialog("Keep deleted messages forever?", isPresented: $confirmingForever) {
            Button("Keep Forever") { retentionDays = 0 }
        } message: {
            Text("They will stay on this Mac until you erase the archive.")
        }
        .confirmationDialog("Erase the archive?", isPresented: $confirmingErase) {
            Button("Erase", role: .destructive) {
                Task {
                    if let archive = try? Self.archive() { await archive.eraseAll() }
                    await refresh()
                }
            }
        } message: {
            Text("Every kept deleted message is removed from this Mac. This cannot be undone.")
        }
    }

    private func refresh() async {
        // Reading statistics needs the archive key; don't ask for it while off.
        guard keepDeleted, let archive = try? Self.archive() else { stats = nil; return }
        stats = await archive.statistics()
    }

    private static func archive() throws -> MessageArchive {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try MessageArchive.shared(directory: support.appendingPathComponent("Nodogram/accounts/default"))
    }
}

// MARK: - Notifications

private struct NotificationSettings: View {
    @AppStorage(AppModel.notificationsEnabledKey) private var enabled = true
    @AppStorage(SystemNotifications.privacyModeKey) private var privacyMode = false
    @AppStorage(AppModel.dockBadgeKey) private var dockBadge = true

    var body: some View {
        Form {
            Section {
                Toggle("Show notifications for new messages", isOn: $enabled)
                Toggle("Hide message text and sender", isOn: $privacyMode)
                    .disabled(!enabled)
                Toggle("Show unread count on the Dock icon", isOn: $dockBadge)
            } footer: {
                Text("""
                    Muted chats never notify, following your Telegram settings. With text hidden, \
                    banners say only that a new message arrived — useful when sharing your screen.
                    """)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Open macOS Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } footer: {
                Text("Banner style, sounds and Focus are controlled by macOS.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Playback

private struct PlaybackSettings: View {
    var body: some View {
        Form {
            Section("Videos") {
                Text("Videos continue from where you stopped. Use “Start over” in the player to begin again.")
                    .foregroundStyle(.secondary)
                LabeledContent("Back / forward 10 seconds", value: "← →   or   J  L")
                LabeledContent("Play / pause", value: "Space  or  K")
                LabeledContent("Previous / next item", value: "⌥←  ⌥→")
                LabeledContent("Save / Show in Finder", value: "⌘S   ⌘⇧R")
            }
            Section("Voice messages") {
                Text("Click the speed badge while playing to switch between 1×, 1.5× and 2×. The next voice message plays automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text("Nodogram").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                .foregroundStyle(.secondary)
            Text(L10n.unofficialDisclosure)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
