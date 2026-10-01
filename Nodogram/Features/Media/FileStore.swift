//  Live download state, one observable object per file.
//
//  A download reports progress many times a second. If progress lived in one
//  big dictionary on AppModel, every tick would re-render every view that reads
//  any file. Here each view observes only its own file's object.

import Foundation
import Observation
import NodogramDomain

@MainActor
@Observable
public final class FileState {
    public private(set) var file: MediaFile

    init(file: MediaFile) {
        self.file = file
    }

    func update(_ newer: MediaFile) {
        // Never regress a completed file to "incomplete" because an older
        // snapshot arrived late.
        if file.isComplete && !newer.isComplete && newer.id == file.id { return }
        if newer != file { file = newer }
    }
}

@MainActor
public final class FileStore {
    private var states: [Int: FileState] = [:]

    /// The live state for a file, seeded from the snapshot in a message.
    public func state(for file: MediaFile) -> FileState {
        if let existing = states[file.id] {
            existing.update(file)
            return existing
        }
        let state = FileState(file: file)
        states[file.id] = state
        return state
    }

    func apply(_ file: MediaFile) {
        if let existing = states[file.id] {
            existing.update(file)
        } else {
            states[file.id] = FileState(file: file)
        }
    }

    func current(_ fileID: Int) -> MediaFile? {
        states[fileID]?.file
    }
}
