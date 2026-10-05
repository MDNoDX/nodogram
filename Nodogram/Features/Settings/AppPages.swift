//  Settings pages that live on this Mac: general behaviour, storage,
//  appearance, and Nodogram's own features.

import SwiftUI
import AppKit
import NodogramCore
import NodogramDomain
import NodogramPlatform
import NodogramUI

// MARK: - General

struct GeneralPage: View {
    @AppStorage("composer.sendWithEnter") private var sendWithEnter = true
    @AppStorage("media.autoplayGIFs") private var autoplayGIFs = true
    @AppStorage("media.autoDownloadPhotos") private var autoDownloadPhotos = true
    @AppStorage("links.askBeforeOpening") private var askBeforeOpening = true

    var body: some View {
        SettingsForm {
            Section("Input") {
                Picker("Send messages with", selection: $sendWithEnter) {
                    Text("↩ Return  (⇧↩ for a new line)").tag(true)
                    Text("⌘↩ Command-Return").tag(false)
                }
            }
            Section("Media") {
                Toggle("Download photos automatically", isOn: $autoDownloadPhotos)
                Toggle("Play GIFs automatically", isOn: $autoplayGIFs)
            }
            Section {
                Toggle("Ask before opening unusual links", isOn: $askBeforeOpening)
            } header: { Text("Links") } footer: {
                SettingsNote("Web, mail, phone and Telegram links always open directly. Others — such as file: or custom app links — ask first while this is on.")
            }
            Section("Keyboard") {
                LabeledContent("Quick open", value: "⌘K")
                LabeledContent("Find in chat", value: "⌘F")
                LabeledContent("Folders and sections", value: "⌘1 … ⌘9")
                LabeledContent("Attach a file", value: "⌘O")
                LabeledContent("Settings", value: "⌘,")
                LabeledContent("Video: back / forward 10 s", value: "← →   J L")
            }
        }
    }
}

// MARK: - Data and storage

struct DataStoragePage: View {
    let model: AppModel

    @State private var folder = MediaLibrary.folder
    @AppStorage(MediaLibrary.autoSaveKey) private var autoSave = false
    @State private var usage: StorageUsage?
    @State private var confirmingClear = false
    @State private var clearing = false

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "externaldrive.fill", tint: SettingsPage.dataStorage.tint,
                             text: "Where your files go, and how much space Telegram's cache uses on this Mac.")
            }
            Section("Storage usage") {
                if let usage {
                    LabeledContent("Cached media", value: ByteCountFormatter.string(fromByteCount: usage.filesSize, countStyle: .file))
                    LabeledContent("Files", value: "\(usage.fileCount)")
                    LabeledContent("Database", value: ByteCountFormatter.string(fromByteCount: usage.databaseSize, countStyle: .file))
                    Button(clearing ? "Clearing…" : "Clear Cache…", role: .destructive) { confirmingClear = true }
                        .disabled(clearing || usage.filesSize == 0)
                } else {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                }
            }
            Section {
                LabeledContent("Save files to") {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().frame(width: 18, height: 18)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
                        Button("Change…", action: choose)
                    }
                }
                HStack {
                    Button("Show in Finder") { MediaLibrary.openFolder() }
                    if folder != MediaLibrary.defaultFolder {
                        Button("Use Default") { MediaLibrary.resetFolder(); folder = MediaLibrary.folder }
                    }
                }
                Toggle("Also copy every downloaded file here", isOn: $autoSave)
            } header: { Text("Downloads") } footer: {
                SettingsNote("“Save” and “Show in Finder” copy files here. Media in chats that forbid saving is never copied. Use “Save As…” on any file to pick a place each time.")
            }
        }
        .task { usage = await model.storageUsage() }
        .confirmationDialog("Clear the media cache?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) {
                clearing = true
                Task {
                    await model.clearCache()
                    usage = await model.storageUsage()
                    clearing = false
                }
            }
        } message: { Text("Photos, videos and files are removed from this Mac. They stay in your chats and download again when opened.") }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            MediaLibrary.setFolder(url)
            folder = url
        }
    }
}

// MARK: - Appearance

struct AppearancePage: View {
    @AppStorage(Theme.colorSchemeKey) private var scheme = "system"
    @AppStorage(Theme.accentKey) private var accent = 0
    @AppStorage(Theme.textSizeKey) private var textSize = 13.5
    @AppStorage(Theme.wallpaperKey) private var wallpaper = 0
    @AppStorage(Theme.solidBubblesKey) private var solidBubbles = false
    @AppStorage("chatList.showFolderTags") private var folderTags = false
    @AppStorage("general.largeEmoji") private var largeEmoji = true

    /// Ready-made looks, as in Telegram's Appearance: each sets the scheme,
    /// accent, bubbles and background together.
    private struct Preset: Identifiable {
        let id: String
        let scheme: String
        let accent: Int
        let solid: Bool
        let wallpaper: Int
    }

    private let presets: [Preset] = [
        Preset(id: "Day", scheme: "light", accent: 1, solid: true, wallpaper: 0),
        Preset(id: "Day Classic", scheme: "light", accent: 3, solid: false, wallpaper: 3),
        Preset(id: "Night", scheme: "dark", accent: 0, solid: false, wallpaper: 0),
        Preset(id: "Night Accent", scheme: "dark", accent: 1, solid: true, wallpaper: 5),
        Preset(id: "System", scheme: "system", accent: 0, solid: false, wallpaper: 0),
    ]

    var body: some View {
        SettingsForm {
            Section { preview.listRowInsets(EdgeInsets()) }

            Section("Colour theme") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(presets) { preset in presetCard(preset) }
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 10) {
                    ForEach(Theme.accentChoices.indices, id: \.self) { index in
                        Button { accent = index } label: {
                            Circle().fill(Theme.accentChoices[index].color)
                                .frame(width: 28, height: 28)
                                .overlay { if accent == index { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
                                .overlay(Circle().stroke(Theme.accentChoices[index].color, lineWidth: accent == index ? 2 : 0).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .help(Theme.accentChoices[index].name)
                    }
                }
                .padding(.vertical, 4)
                Toggle("Dark Mode", isOn: Binding(get: { scheme == "dark" }, set: { scheme = $0 ? "dark" : "light" }))
                Toggle("Coloured outgoing bubbles", isOn: $solidBubbles)
                Picker("Auto-Night Mode", selection: $scheme) {
                    Text("Follow System").tag("system")
                    Text("Always Light").tag("light")
                    Text("Always Dark").tag("dark")
                }
            }

            Section("Chat wallpaper") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Theme.wallpapers.indices, id: \.self) { index in
                            wallpaperSwatch(index)
                        }
                        Button(action: chooseWallpaper) {
                            VStack(spacing: 4) {
                                Group {
                                    if wallpaper == Theme.customWallpaperIndex, let image = Theme.customWallpaperImage {
                                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                    } else {
                                        Image(systemName: "photo.badge.plus").font(.system(size: 18)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 62, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: wallpaper == Theme.customWallpaperIndex ? 2 : 0))
                                Text("Picture…").font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                Text("Any chat can have its own: ⋯ → Change Wallpaper.").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Section("Text size") {
                HStack(spacing: 10) {
                    Text("A").font(.system(size: 11))
                    Slider(value: $textSize, in: 12...18, step: 0.5)
                    Text("A").font(.system(size: 18))
                    Text("\(textSize, specifier: "%.1f")").monospacedDigit().foregroundStyle(.secondary).frame(width: 34)
                }
            }

            Section {
                Toggle("Show folder tags in the chat list", isOn: $folderTags)
                Toggle("Large emoji in messages that are only emoji", isOn: $largeEmoji)
            } header: { Text("Chat list and messages") }
        }
    }

    private var preview: some View {
        let colors = wallpaper == Theme.customWallpaperIndex ? [] : Theme.wallpapers[Theme.wallpapers.indices.contains(wallpaper) ? wallpaper : 0].colors
        let accentColor = Theme.accentChoices[Theme.accentChoices.indices.contains(accent) ? accent : 0].color
        return VStack(alignment: .leading, spacing: 8) {
            bubble("Good morning! 👋", outgoing: true, accentColor: accentColor, time: "9:18")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1).fill(accentColor).frame(width: 2.5)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("You").font(.system(size: textSize - 1.5, weight: .semibold)).foregroundStyle(accentColor)
                        Text("Good morning! 👋").font(.system(size: textSize - 1.5)).foregroundStyle(.secondary)
                    }
                }
                .padding(6)
                .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                Text("Do you know what time it is? ⏰").font(.system(size: textSize))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 16))
            bubble("It's morning in Tashkent ☀️", outgoing: true, accentColor: accentColor, time: "9:22")
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 190)
        .background {
            if wallpaper == Theme.customWallpaperIndex, let image = Theme.customWallpaperImage {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if !colors.isEmpty {
                LinearGradient(colors: colors.map { $0.opacity(3) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color.secondary.opacity(0.06)
            }
        }
        .clipped()
        .environment(\.colorScheme, scheme == "dark" ? .dark : scheme == "light" ? .light : .dark)
    }

    private func bubble(_ text: String, outgoing: Bool, accentColor: Color, time: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(text).font(.system(size: textSize))
            Text(time).font(.system(size: 10.5)).opacity(0.7)
        }
        .foregroundStyle(solidBubbles ? .white : .primary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(solidBubbles ? AnyShapeStyle(accentColor) : AnyShapeStyle(accentColor.opacity(0.17)),
                    in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func presetCard(_ preset: Preset) -> some View {
        let dark = preset.scheme == "dark"
        let selected = scheme == preset.scheme && accent == preset.accent && solidBubbles == preset.solid && wallpaper == preset.wallpaper
        let color = Theme.accentChoices[preset.accent].color
        return Button {
            scheme = preset.scheme; accent = preset.accent; solidBubbles = preset.solid; wallpaper = preset.wallpaper
        } label: {
            VStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 5).fill(dark ? Color(white: 0.25) : .white).frame(width: 38, height: 9)
                    RoundedRectangle(cornerRadius: 5).fill(preset.solid ? color : color.opacity(0.35)).frame(width: 46, height: 9)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(8)
                .frame(width: 80, height: 54)
                .background(preset.scheme == "system"
                            ? AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.15)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(dark ? Color(white: 0.12) : Color(white: 0.94)),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1))
                Text(preset.id).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : .primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func wallpaperSwatch(_ index: Int) -> some View {
        Button { wallpaper = index } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.wallpapers[index].colors.isEmpty
                          ? AnyShapeStyle(Color.secondary.opacity(0.08))
                          : AnyShapeStyle(LinearGradient(colors: Theme.wallpapers[index].colors.map { $0.opacity(4) },
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .frame(width: 62, height: 46)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent, lineWidth: wallpaper == index ? 2 : 0))
                Text(Theme.wallpapers[index].name).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use as Wallpaper"
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else { return }
        try? FileManager.default.createDirectory(at: Theme.customWallpaperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? jpeg.write(to: Theme.customWallpaperURL, options: .atomic)
        wallpaper = Theme.customWallpaperIndex
    }
}

// MARK: - Nodogram features

struct FeaturesPage: View {
    let model: AppModel

    @AppStorage(AppModel.keepDeletedKey) private var keepDeleted = true
    @AppStorage(AppModel.deletedRetentionKey) private var retentionDays = 365
    @AppStorage(TrackerSettings.deletedNotifyKey) private var deletedNotify = true
    @AppStorage(TrackerSettings.typingScopeKey) private var typingScope = "private"
    @AppStorage(TrackerSettings.typingNotifyKey) private var typingNotify = true
    @AppStorage(TrackerSettings.typingAbandonedNotifyKey) private var abandonedNotify = true
    @AppStorage(TrackerSettings.storyViewsNotifyKey) private var storyNotify = true
    @AppStorage(TrackerSettings.keywordsKey) private var keywords = ""
    @AppStorage(TrackerSettings.streamerModeKey) private var streamerMode = false
    @State private var stats: MessageArchive.Statistics?
    @State private var confirmingErase = false

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "sparkles", tint: SettingsPage.nodogramFeatures.tint,
                             text: "Things Telegram shows for a moment, kept on this Mac so you can look later. Nothing here changes what others see.")
            }

            Section {
                if let vault = model.vaultStatus {
                    LabeledContent("Status") {
                        Label(vault.connected ? "Connected to your account" : "Running — not connected yet",
                              systemImage: vault.connected ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(vault.connected ? Theme.success : Theme.warning)
                    }
                    LabeledContent("Kept", value: "\(vault.kept) messages · \(vault.deleted) deleted · \(vault.edited) edited")
                } else {
                    LabeledContent("Status") {
                        Label("Not running on this Mac", systemImage: "xmark.octagon").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Open the Bot in Telegram") {
                        if let url = URL(string: "https://t.me/MDNoDX_bot") { NSWorkspace.shared.open(url) }
                    }
                    Button("Check Now") { Task { await model.syncVault() } }
                }
            } header: { Label("Nodogram Vault — always on", systemImage: "lock.shield") } footer: {
                SettingsNote("""
                    Your own Telegram Business bot keeps every message in your private chats, even when Nodogram \
                    is closed: Telegram holds the bot's updates for 24 hours, and the Vault service on this Mac \
                    collects them. When someone deletes or edits a message, the bot sends it to you at once — \
                    on your phone too — and it appears here in that chat and under Deleted, photos and voice included. \
                    To connect: in @BotFather turn on Business Mode for the bot, press Start in the bot, then \
                    Telegram → Settings → Telegram Business → Chatbots → add the bot for all 1-to-1 chats.
                    """)
            }

            Section {
                Toggle("Keep messages others delete", isOn: $keepDeleted)
                Toggle("Notify me when someone deletes a message", isOn: $deletedNotify).disabled(!keepDeleted)
                Picker("Keep deleted messages for", selection: $retentionDays) {
                    Text("30 days").tag(30)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
                .disabled(!keepDeleted)
                if let stats, keepDeleted {
                    LabeledContent("Kept on this Mac", value: "\(stats.deleted) deleted · \(stats.received) recent")
                }
                Button("Erase Kept Messages…", role: .destructive) { confirmingErase = true }
            } header: { Label("Deleted messages", systemImage: "trash.circle") } footer: {
                SettingsNote("""
                    Deleted messages stay in the chat, marked “Deleted”, and are listed under Deleted. Edits keep \
                    every earlier version — click “edited” on a message. Only messages this Mac received are kept; \
                    self-destructing and copy-protected ones never are. Encrypted with a key in your Keychain.
                    """)
            }

            Section {
                Picker("Track typing in", selection: $typingScope) {
                    Text("Private chats").tag("private")
                    Text("All chats").tag("all")
                    Text("Off").tag("off")
                }
                Toggle("Notify when someone starts typing to me", isOn: $typingNotify).disabled(typingScope == "off")
                Toggle("Notify when someone types but sends nothing", isOn: $abandonedNotify).disabled(typingScope == "off")
                LabeledContent("Logged", value: "\(model.typingLog.count) events")
                Button("Clear Typing Log", role: .destructive) { model.clearTypingLog() }
                    .disabled(model.typingLog.isEmpty)
            } header: { Label("Typing", systemImage: "ellipsis.bubble") } footer: {
                SettingsNote("Who started typing, when, for how long, and whether a message followed. Muted chats never notify.")
            }

            Section {
                Toggle("Notify when someone views my story", isOn: $storyNotify)
                LabeledContent("Viewers kept", value: "\(model.storyViewers.count)")
                Button("Clear Story Viewers", role: .destructive) { model.clearStoryViewers() }
                    .disabled(model.storyViewers.isEmpty)
            } header: { Label("Story views", systemImage: "eye.circle") } footer: {
                SettingsNote("Telegram lists viewers only while a story is live. Nodogram checks every minute while it runs and keeps the list for good.")
            }

            Section {
                TextField("e.g. meeting, invoice, my name", text: $keywords)
            } header: { Label("Keyword alerts", systemImage: "bell.and.waves.left.and.right") } footer: {
                SettingsNote("Get a notification when any of these words appears — even in muted chats and channels. Separate words with commas.")
            }

            Section {
                Toggle("Streamer mode", isOn: $streamerMode)
            } header: { Label("Screen sharing", systemImage: "rectangle.on.rectangle.slash") } footer: {
                SettingsNote("Blurs message previews in the chat list and hides notification text, for screen sharing and presentations. ⌘⇧H toggles it.")
            }
        }
        .task(id: keepDeleted) { await refresh() }
        .confirmationDialog("Erase kept messages?", isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) {
                Task {
                    if let archive = model.archive { await archive.eraseAll() }
                    await refresh()
                }
            }
        } message: { Text("Every kept deleted message and edit history is removed from this Mac.") }
    }

    private func refresh() async {
        guard keepDeleted else { stats = nil; return }
        if model.archive == nil, let directory = model.archiveDirectory { model.openArchive(in: directory) }
        stats = await model.archive?.statistics()
    }
}

// MARK: - Language

struct LanguagePage: View {
    @AppStorage("translate.target") private var target = "uz"

    private static let languages: [(String, String)] = [
        ("uz", "Oʻzbekcha"), ("ru", "Русский"), ("en", "English"), ("tr", "Türkçe"),
        ("ar", "العربية"), ("kk", "Қазақша"), ("de", "Deutsch"), ("fr", "Français"),
    ]

    var body: some View {
        SettingsForm {
            Section {
                LabeledContent("Interface", value: "English")
            } header: { Text("Interface language") } footer: {
                SettingsNote("Nodogram's own interface is in English for now.")
            }
            Section {
                Picker("Translate messages to", selection: $target) {
                    ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                }
            } header: { Text("Translation") } footer: {
                SettingsNote("Right-click a message and choose Translate. Translation is done by Telegram.")
            }
        }
    }
}

// MARK: - About

struct AboutPage: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                    Text("Nodogram").font(.title2.weight(.semibold))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                    if let td = model.tdlibVersion {
                        Text("TDLib \(td)").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    Text(L10n.unofficialDisclosure)
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            Section {
                Link("Source code on GitHub", destination: URL(string: "https://github.com/MDNoDX/nodogram")!)
                Link("Telegram FAQ", destination: URL(string: "https://telegram.org/faq")!)
                Link("Telegram Privacy Policy", destination: URL(string: "https://telegram.org/privacy")!)
            }
        }
    }
}
