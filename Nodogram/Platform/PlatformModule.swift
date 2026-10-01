//  NodogramPlatform — macOS system integration.
//
//  Near-empty by design; see the note in NodogramCore/CoreModule.swift about
//  why this file exists rather than a "Placeholder".
//
//  Planned contents, per Documentation/ARCHITECTURE.md §11:
//    notifications with actions and grouping (brief §29, §59)
//    Focus mode integration (brief §30)
//    Quick Look previews, Share sheet, Finder reveal (brief §24)
//    Spotlight indexing of local-only data, opt-in (brief §3)
//    sleep/wake observation, used to flush drafts before sleep (brief §10)

import Foundation

/// Identifies this module in logs and diagnostics.
public enum PlatformModule {
    public static let name = "NodogramPlatform"
}
