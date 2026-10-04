//  Renders the poll view in every state to PNGs, so its appearance can be
//  inspected without opening anyone's chat. Images go to
//  $TMPDIR/nodogram-snapshots/.

import Testing
import SwiftUI
import AppKit
@testable import NodogramFeatures
import NodogramDomain
import NodogramUI

@MainActor
@Suite("Poll snapshots", .serialized)
struct PollSnapshotTests {

    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("nodogram-snapshots")

    private func options(_ texts: [String], votes: [Int] = [], chosen: Set<Int> = []) -> [PollContent.Option] {
        let total = max(1, votes.reduce(0, +))
        return texts.enumerated().map { index, text in
            let count = index < votes.count ? votes[index] : 0
            return PollContent.Option(index: index, text: text, voterCount: count,
                                      percentage: Int((Double(count) / Double(total) * 100).rounded()),
                                      isChosen: chosen.contains(index))
        }
    }

    private var cases: [(String, PollContent)] {
        let texts = ["Ertaga soat 10:00 da", "Payshanba kuni", "Keyingi hafta", "Menga farqi yo'q"]
        let votes = [42, 18, 9, 31]
        return [
            ("1-not-voted", PollContent(id: 1, question: "Uchrashuvni qachon o'tkazamiz?",
                                        options: options(texts), totalVoters: 100)),
            ("2-voted", PollContent(id: 2, question: "Uchrashuvni qachon o'tkazamiz?",
                                    options: options(texts, votes: votes, chosen: [0]), totalVoters: 100)),
            ("3-multiple", PollContent(id: 3, question: "Qaysi tillarni bilasiz?",
                                       options: options(["O'zbek", "Rus", "Ingliz", "Turk"]),
                                       totalVoters: 1234, allowsMultipleAnswers: true)),
            ("4-quiz-wrong", PollContent(id: 4, question: "O'zbekiston poytaxti qaysi shahar?",
                                         options: options(["Samarqand", "Toshkent", "Buxoro"], votes: [12, 70, 18], chosen: [0]),
                                         totalVoters: 100,
                                         kind: .quiz(correct: [1], explanation: "Toshkent 1930-yildan beri poytaxt."))),
            ("5-closed-public", PollContent(id: 5, question: "Yangi dizayn yoqdimi?",
                                            details: "Ovoz berish yakunlandi.",
                                            options: options(["Ha", "Yo'q"], votes: [87, 13]),
                                            totalVoters: 100, isAnonymous: false, isClosed: true)),
            ("6-restricted", PollContent(id: 6, question: "Kanal uchun yangi nom?",
                                         options: options(["Variant A", "Variant B"]),
                                         totalVoters: 4, restriction: .membership)),
        ]
    }

    @Test("Render every poll state, light and dark")
    func renderAll() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        for (name, poll) in cases {
            for scheme in [ColorScheme.light, .dark] {
                let view = PollView(poll: poll, isOutgoing: false, onVote: { _ in }, onRetract: {})
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.bubbleIncoming, in: RoundedRectangle(cornerRadius: 16))
                    .padding(20)
                    .frame(width: 420)
                    .background(scheme == .dark ? Color(white: 0.11) : Color(white: 0.97))
                    .environment(\.colorScheme, scheme)

                // NSHostingView, not ImageRenderer: ImageRenderer cannot draw
                // native AppKit controls and substitutes placeholders for them.
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: Self.directory.appendingPathComponent("poll-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
