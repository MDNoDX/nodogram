//  Renders the settings pages and new sections offscreen, so their layout can
//  be inspected without a signed-in account. Images go to
//  $TMPDIR/nodogram-snapshots/.

import Testing
import SwiftUI
import AppKit
@testable import NodogramFeatures
import NodogramDomain

@MainActor
@Suite("Settings snapshots", .serialized)
struct SettingsSnapshotTests {

    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nodogram-snapshots")

    private func render<V: View>(_ view: V, _ name: String, size: CGSize = CGSize(width: 760, height: 900)) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: Self.directory.appendingPathComponent("\(name).png"))
    }

    @Test("Render settings pages")
    func pages() throws {
        let model = AppModel()
        try render(AppearancePage(), "settings-appearance")
        try render(GeneralPage(), "settings-general")
        try render(FeaturesPage(model: model), "settings-features", size: CGSize(width: 760, height: 1400))
        try render(SidebarPage(model: model), "settings-sidebar", size: CGSize(width: 760, height: 1100))
        try render(FoldersPage(model: model), "settings-folders")
        try render(FolderEditorPage(model: model, folderID: nil), "settings-folder-editor", size: CGSize(width: 760, height: 1100))
        try render(SettingsListView(model: model), "settings-list", size: CGSize(width: 340, height: 800))
    }
}
