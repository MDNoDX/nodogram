//  The composer's sticker / GIF picker: favourite and recent stickers and your
//  saved GIFs in a grid; tap one to send it. Thumbnails load lazily.

import SwiftUI
import NodogramDomain

struct StickerPickerView: View {
    let sections: () async -> StickerSections
    let loadThumb: (StickerPickItem) async -> String?
    let onPick: (StickerPickItem) -> Void
    let onClearRecent: () -> Void

    @State private var loaded = StickerSections()
    @State private var tab = 0   // 0 = stickers, 1 = GIFs
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Stickers").tag(0)
                Text("GIFs").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().padding(8)
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if (tab == 0 && loaded.favorites.isEmpty && loaded.recent.isEmpty) || (tab == 1 && loaded.gifs.isEmpty) {
                VStack(spacing: 6) {
                    Image(systemName: tab == 0 ? "face.smiling" : "rectangle.stack.badge.play").font(.largeTitle).foregroundStyle(.secondary)
                    Text(tab == 0 ? "No stickers yet" : "No saved GIFs").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if tab == 0 {
                        if !loaded.favorites.isEmpty { grid("Favourites", loaded.favorites) }
                        if !loaded.recent.isEmpty { grid("Recent", loaded.recent) }
                    } else {
                        grid(nil, loaded.gifs)
                    }
                }
            }
            Divider()
            HStack {
                if tab == 0 {
                    Button("Clear Recent", role: .destructive) { onClearRecent(); Task { await reload() } }
                        .controlSize(.small)
                }
                Spacer()
                Button("Done") { dismiss() }.controlSize(.small)
            }
            .padding(8)
        }
        .frame(width: 340, height: 420)
        .task { await reload() }
    }

    private func grid(_ title: String?, _ items: [StickerPickItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 8)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 6), count: 4), spacing: 6) {
                ForEach(items) { item in
                    StickerCell(item: item, loadThumb: loadThumb) { onPick(item); dismiss() }
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
        }
    }

    private func reload() async {
        loading = true
        loaded = await sections()
        loading = false
    }
}

private struct StickerCell: View {
    let item: StickerPickItem
    let loadThumb: (StickerPickItem) async -> String?
    let onTap: () -> Void
    @State private var path: String?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4))
                if let path, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().scaledToFit().padding(6)
                } else if !item.emoji.isEmpty {
                    Text(item.emoji).font(.system(size: 26))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 72, height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.emoji)
        .task(id: item.id) { if path == nil { path = await loadThumb(item) } }
    }
}
