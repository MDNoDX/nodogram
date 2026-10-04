//  Where downloaded media goes, and the Finder actions around it.
//
//  TDLib keeps downloads in its own cache inside Application Support, which is
//  not a place anyone should browse to. "Save" and "Show in Finder" therefore
//  copy the file into a folder the user chose — ~/Downloads/Nodogram unless
//  changed in Settings → Storage — and reveal it there.

import AppKit
import Foundation

public enum MediaLibrary {

    public static let folderKey = "storage.downloadFolder"
    public static let autoSaveKey = "storage.autoSave"
    private static let savedMapKey = "storage.savedFiles"

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nodogram", isDirectory: true)
    }

    /// The folder the user chose, or the default.
    public static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: folderKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultFolder
    }

    public static func setFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: folderKey)
    }

    public static func resetFolder() {
        UserDefaults.standard.removeObject(forKey: folderKey)
    }

    /// Whether files the user downloads are copied to the folder automatically.
    public static var autoSave: Bool {
        UserDefaults.standard.bool(forKey: autoSaveKey)
    }

    /// The saved copy of a file, if one exists and is still on disk.
    public static func savedCopy(uniqueID: String) -> URL? {
        guard let path = savedMap()[uniqueID] else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copies a downloaded file into the media folder, once. Saving the same
    /// file again returns the existing copy instead of making "file (2).mp4".
    @discardableResult
    public static func save(localPath: String, suggestedName: String, uniqueID: String) throws -> URL {
        if let existing = savedCopy(uniqueID: uniqueID) { return existing }

        let directory = folder
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = uniqueDestination(in: directory, name: sanitize(suggestedName))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: localPath), to: destination)
        Quarantine.mark(destination.path)

        var map = savedMap()
        map[uniqueID] = destination.path
        UserDefaults.standard.set(map, forKey: savedMapKey)
        return destination
    }

    /// Saves (if needed) and selects the file in Finder.
    public static func revealInFinder(localPath: String, suggestedName: String, uniqueID: String) throws {
        let url = try save(localPath: localPath, suggestedName: suggestedName, uniqueID: uniqueID)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// Opens a file in its default app — for documents, not for media, which
    /// plays inside Nodogram.
    /// Files that can run code get the quarantine attribute and a warning first,
    /// so Gatekeeper checks them like any other download.
    @MainActor
    public static func open(localPath: String) {
        Quarantine.mark(localPath)
        guard Quarantine.confirmOpening(localPath) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: localPath))
    }

    private static func savedMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: savedMapKey) as? [String: String] ?? [:]
    }

    private static func sanitize(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "File" : cleaned
    }

    private static func uniqueDestination(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }
}
