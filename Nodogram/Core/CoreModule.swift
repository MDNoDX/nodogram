//  NodogramCore — local storage, security, search and synchronization.
//
//  This target is deliberately near-empty right now. Swift Package Manager
//  requires every target to have at least one source file, so rather than a
//  file called "Placeholder" that pretends to be something, this one states
//  plainly what the target is for and when it gets filled.
//
//  Planned contents, per Documentation/ARCHITECTURE.md §11:
//    Database/        GRDB + SQLCipher, the schema in DATA_MODEL.md
//    Security/        Keychain, key hierarchy, app lock
//    Search/          SQLite FTS5 index over local-only data
//    Synchronization/ the single ordered consumer of the gateway's updates
//    Storage/         media cache with bounded eviction
//
//  GRDB is already a declared dependency of this target, so the database work
//  can begin without touching the package manifest.

import Foundation

/// Identifies this module in logs and diagnostics.
public enum CoreModule {
    public static let name = "NodogramCore"
}
