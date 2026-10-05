//  Message filters: hide messages containing chosen words, or from chosen
//  people, on this Mac only. A hidden message leaves a thin "hidden" line you
//  can click to read it — nothing is deleted.

import Foundation
import SwiftUI
import NodogramDomain
import NodogramUI

public enum MessageFilterSettings {
    public static let keywordsKey = "filters.keywords"
    public static let sendersKey = "filters.senders"
    public static let enabledKey = "filters.enabled"

    public static var keywords: [String] {
        (UserDefaults.standard.string(forKey: keywordsKey) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    public static var senders: Set<Int64> {
        Set((UserDefaults.standard.array(forKey: sendersKey) as? [Int64]) ?? [])
    }

    public static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Why a message is hidden, or nil.
    public static func reason(for message: Message) -> String? {
        guard isEnabled, !message.isOutgoing else { return nil }
        if let sender = message.senderID, senders.contains(sender.rawValue) { return "from \(message.senderName)" }
        let text = message.text.lowercased()
        if let word = keywords.first(where: { text.contains($0) }) { return "contains “\(word)”" }
        return nil
    }

    public static func hideSender(_ id: UserID) {
        var list = (UserDefaults.standard.array(forKey: sendersKey) as? [Int64]) ?? []
        if !list.contains(id.rawValue) { list.append(id.rawValue) }
        UserDefaults.standard.set(list, forKey: sendersKey)
    }

    public static func unhideSender(_ id: Int64) {
        let list = ((UserDefaults.standard.array(forKey: sendersKey) as? [Int64]) ?? []).filter { $0 != id }
        UserDefaults.standard.set(list, forKey: sendersKey)
    }
}

struct FilteredMessageLine: View {
    let reason: String
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Hidden by your filter (\(reason)) · Show")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FiltersPage: View {
    let model: AppModel
    @AppStorage(MessageFilterSettings.keywordsKey) private var keywords = ""
    @AppStorage(MessageFilterSettings.enabledKey) private var enabled = true
    @State private var senders: [Int64] = Array(MessageFilterSettings.senders)

    var body: some View {
        SettingsForm {
            Section {
                SettingsHero(symbol: "line.3.horizontal.decrease.circle.fill", tint: SettingsPage.filters.tint,
                             text: "Hide messages you don't want to see — by words or by person. They stay on Telegram; here they shrink to a line you can open.")
            }
            Section {
                Toggle("Use filters", isOn: $enabled)
                TextField("Words to hide, separated by commas", text: $keywords, axis: .vertical)
                    .lineLimit(1...4)
            } header: { Text("Words") }
            Section {
                if senders.isEmpty {
                    Text("None. In a group, right-click someone's message and choose “Hide Messages from …”.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(senders, id: \.self) { id in
                    HStack {
                        Text(model.chatsByID[ChatID(id)]?.title ?? model.userNameForFilter(id))
                        Spacer()
                        Button("Show Again") {
                            MessageFilterSettings.unhideSender(id)
                            senders = Array(MessageFilterSettings.senders)
                        }
                    }
                }
            } header: { Text("People") }
        }
    }
}

extension AppModel {
    func userNameForFilter(_ id: Int64) -> String { gateway?.userName(UserID(id)) ?? "User \(id)" }
}
