//  Export Chat History: every message of a chat as a readable HTML page and a
//  JSON file, deleted messages kept on this Mac included and marked.

import AppKit
import Foundation
import NodogramDomain

extension AppModel {

    public func exportChat(_ chatID: ChatID) {
        guard let gateway else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the exported chat"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let title = chatTitle(chatID)
        exportProgress = 0
        Task { [weak self] in
            guard let self else { return }
            var all: [Message] = []
            var before: MessageID?
            while all.count < 200_000 {
                guard let page = try? await gateway.history(chatID, before: before, limit: 100), !page.isEmpty else { break }
                let fresh = page.filter { m in !all.contains { $0.id == m.id } }
                if fresh.isEmpty { break }
                all += fresh
                before = page.map(\.id).min { $0.rawValue < $1.rawValue }
                self.exportProgress = all.count
            }
            all = await self.mergingDeleted(into: all.sorted { $0.id.rawValue < $1.id.rawValue }, chatID: chatID, openEnded: false)
            let stamp = Date().formatted(.iso8601.year().month().day())
            let base = folder.appendingPathComponent("\(title.replacingOccurrences(of: "/", with: "-")) \(stamp)")
            do {
                try Self.exportHTML(all, title: title).write(to: base.appendingPathExtension("html"), atomically: true, encoding: .utf8)
                try Self.exportJSON(all).write(to: base.appendingPathExtension("json"), options: .atomic)
                self.exportProgress = nil
                self.showToast("Exported \(all.count) messages")
                NSWorkspace.shared.activateFileViewerSelecting([base.appendingPathExtension("html")])
            } catch {
                self.exportProgress = nil
                self.showToast("Export failed: \(error.localizedDescription)")
            }
        }
    }

    static func exportJSON(_ messages: [Message]) throws -> Data {
        struct Row: Encodable {
            let id: Int64; let date: Date; let from: String; let outgoing: Bool
            let text: String; let attachment: String?; let edited: Date?; let deleted: Date?
        }
        let rows = messages.map { Row(id: $0.id.rawValue >> 20, date: $0.date, from: $0.isOutgoing ? "You" : $0.senderName,
                                      outgoing: $0.isOutgoing, text: $0.text, attachment: $0.attachmentLabel,
                                      edited: $0.editDate, deleted: $0.deletedAt) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(rows)
    }

    static func exportHTML(_ messages: [Message], title: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        var body = ""
        var lastDay = ""
        for m in messages {
            let day = m.date.formatted(date: .complete, time: .omitted)
            if day != lastDay { body += "<div class=day>\(esc(day))</div>"; lastDay = day }
            let who = m.isOutgoing ? "You" : (m.senderName.isEmpty ? title : m.senderName)
            let attachment = m.attachmentLabel.map { "<div class=att>\(esc($0))</div>" } ?? ""
            let flags = (m.deletedAt != nil ? " <span class=del>deleted</span>" : "") + (m.wasEdited ? " <span class=meta>edited</span>" : "")
            body += """
            <div class="msg \(m.isOutgoing ? "out" : "in")\(m.deletedAt != nil ? " gone" : "")">
            <div class=who>\(esc(who))</div>\(attachment)<div>\(esc(m.text))</div>
            <div class=meta>\(m.date.formatted(date: .omitted, time: .shortened))\(flags)</div></div>
            """
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>\(esc(title))</title><style>
        body{font:15px -apple-system,system-ui,sans-serif;background:#f4f4f7;color:#111;max-width:760px;margin:0 auto;padding:24px}
        h1{font-size:20px}.day{text-align:center;color:#888;margin:18px 0 8px;font-size:12px}
        .msg{background:#fff;border-radius:14px;padding:8px 12px;margin:4px 0;max-width:80%;box-shadow:0 1px 1px #0001}
        .out{margin-left:auto;background:#e3e6fb}.gone{border:1px dashed #d33}.who{font-weight:600;font-size:13px;color:#5c66c7}
        .att{color:#5c66c7;font-size:13px}.meta{color:#888;font-size:11px;text-align:right}.del{color:#d33}
        @media(prefers-color-scheme:dark){body{background:#161618;color:#eee}.msg{background:#242428}.out{background:#2d3060}}
        </style></head><body><h1>\(esc(title))</h1><p class=meta>Exported by Nodogram · \(messages.count) messages</p>
        \(body)</body></html>
        """
    }
}
