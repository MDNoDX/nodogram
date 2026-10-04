//  Save, Show in Finder, Open, Copy — shared by bubbles and the viewer.
//
//  Every action checks `canBeSaved` first. When a chat forbids saving content,
//  Nodogram shows the media but does not export it: that is the chat owner's
//  decision, Telegram's API terms require clients to honour it, and ignoring it
//  would put the user's api_id at risk.

import AppKit
import SwiftUI
import NodogramDomain
import NodogramPlatform

@MainActor
enum MediaActions {

    static func save(_ message: Message, model: AppModel, reveal: Bool) {
        guard message.canBeSaved, let media = message.media else {
            model.showToast("Saving is turned off in this chat.")
            return
        }
        Task {
            guard let file = await model.fetch(media.primaryFile, priority: 24), let path = file.localPath else {
                model.showToast("Couldn't download the file.")
                return
            }
            do {
                if reveal {
                    try MediaLibrary.revealInFinder(localPath: path, suggestedName: media.suggestedFileName,
                                                    uniqueID: file.uniqueID)
                } else {
                    let url = try MediaLibrary.save(localPath: path, suggestedName: media.suggestedFileName,
                                                    uniqueID: file.uniqueID)
                    model.showToast("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
                }
            } catch {
                model.showToast("Couldn't save: \(error.localizedDescription)")
            }
        }
    }

    /// Asks where to put this one file.
    static func saveAs(_ message: Message, model: AppModel) {
        guard message.canBeSaved, let media = message.media else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = media.suggestedFileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            guard let file = await model.fetch(media.primaryFile, priority: 24), let path = file.localPath else {
                model.showToast("Couldn't download the file.")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: destination)
                Quarantine.mark(destination.path)
                model.showToast("Saved “\(destination.lastPathComponent)”")
            } catch {
                model.showToast("Couldn't save: \(error.localizedDescription)")
            }
        }
    }

    /// Documents open in their default app; media plays inside Nodogram.
    static func openDocument(_ message: Message, file: MediaFile, model: AppModel) {
        guard message.canBeSaved else {
            model.showToast("This chat doesn't allow opening files outside Nodogram.")
            return
        }
        Task {
            guard let local = await model.fetch(file, priority: 24), let path = local.localPath else { return }
            MediaLibrary.open(localPath: path)
        }
    }

    static func copyImage(_ message: Message, model: AppModel) {
        guard message.canBeSaved, case .photo(let photo) = message.media else { return }
        Task {
            guard let file = await model.fetch(photo.full, priority: 24), let path = file.localPath,
                  let image = NSImage(contentsOfFile: path) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            model.showToast("Image copied")
        }
    }

    /// Context-menu items for any media message.
    @ViewBuilder
    static func menu(for message: Message, model: AppModel) -> some View {
        if let media = message.media, !message.isDeleted {
            switch media {
            case .photo, .video, .animation:
                Button("Open") { model.openViewer(message) }
            case .document(let doc):
                Button("Open") { openDocument(message, file: doc.file, model: model) }
                    .disabled(!message.canBeSaved)
            default:
                EmptyView()
            }

            if message.canBeSaved {
                Button("Save to \(MediaLibrary.folder.lastPathComponent)") { save(message, model: model, reveal: false) }
                Button("Save As…") { saveAs(message, model: model) }
                Button("Show in Finder") { save(message, model: model, reveal: true) }
                if case .photo = media {
                    Button("Copy Image") { copyImage(message, model: model) }
                }
            } else {
                Text("Saving is turned off in this chat")
            }
            Divider()
        }
    }
}

extension MediaFile {
    var sizeDescription: String {
        size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : ""
    }
}

func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}
