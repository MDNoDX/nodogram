//  The assistant's read on a chat: a warm/interested gauge, what the other
//  person is like, open loops, and advice — with a box to ask follow-ups.

import SwiftUI
import NodogramDomain
import NodogramUI

struct AssistantSheet: View {
    let model: AppModel
    let chat: Chat

    @Environment(\.dismiss) private var dismiss
    @State private var analysis: AssistantAnalysis?
    @State private var stats: ChatStats?
    @State private var error: String?
    @State private var loading = true
    @State private var question = ""
    @State private var answer: String?
    @State private var asking = false
    @State private var goal = ""
    @State private var composed: String?
    @State private var composing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Understanding \(chat.title)", systemImage: "sparkles").font(.headline)
                Spacer()
                if analysis != nil {
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Analyse again")
                }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        HStack { ProgressView().controlSize(.small); Text("Reading your conversation…").foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let error {
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.warning)
                            Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary)
                            if error.contains("Settings") {
                                Button("Open AI Settings") { model.settingsPage = .assistant; model.selectedDestination = .settings; dismiss() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if let analysis {
                        content(analysis)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 620)
        .task { if analysis == nil { await load(force: false) } }
    }

    @ViewBuilder
    private func content(_ a: AssistantAnalysis) -> some View {
        HStack(spacing: 12) {
            gauge("Warmth", a.warmth, "heart.fill", .pink)
            gauge("Interest", a.interest, "bolt.fill", .orange)
        }
        card("Summary", a.summary)
        card("How they feel", a.theirAttitude)
        if let trend = a.interestTrend, !trend.isEmpty { card("Interest trend", trend) }
        card("Your relationship", a.relationship)
        if let p = a.personality, !p.isEmpty { card("Who they seem to be", p) }
        if let c = a.communicationPattern, !c.isEmpty { card("How they communicate", c) }
        card("How they write", a.theirStyle)
        if let stats { localFacts(stats) }
        if let green = a.greenFlags, !green.isEmpty { list("Good signs", green, "checkmark.seal.fill", Theme.success) }
        if let watch = a.watchOuts, !watch.isEmpty { list("Worth noting", watch, "exclamationmark.triangle.fill", Theme.warning) }
        if !a.openLoops.isEmpty { list("Waiting for your reply", a.openLoops, "arrow.turn.down.right", Theme.accent) }
        if !a.topics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOPICS").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                FlowChips(items: a.topics)
            }
        }
        if !a.advice.isEmpty { list("Advice", a.advice, "lightbulb.fill", .yellow) }
        Text("Read \(a.messageCount) messages · \(a.analyzedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.system(size: 10.5)).foregroundStyle(.tertiary)

        if let memory = a.memory, !memory.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("REMEMBERED", systemImage: "brain").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(memory, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 4, height: 4).padding(.top, 6)
                        Text(item).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Kept on this Mac and carried into every analysis and reply.").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }

        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("WRITE A REPLY FOR ME").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                TextField("Your goal, e.g. propose meeting Saturday", text: $goal).textFieldStyle(.roundedBorder).onSubmit(compose)
                Button(composing ? "…" : "Write") { compose() }.disabled(goal.isEmpty || composing)
            }
            if let composed {
                Text(composed).font(.system(size: 13)).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Spacer()
                    Button("Put in Composer") { model.draftText = composed ?? ""; dismiss() }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            }
        }

        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("ASK ABOUT THIS CHAT").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                TextField("e.g. What did they promise me?", text: $question).textFieldStyle(.roundedBorder).onSubmit(ask)
                Button(asking ? "…" : "Ask") { ask() }.disabled(question.isEmpty || asking)
            }
            if let answer {
                Text(answer).font(.system(size: 13)).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func gauge(_ title: String, _ value: Int, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 7)
                Circle().trim(from: 0, to: CGFloat(value) / 100).stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(color)
                    Text("\(value)").font(.system(size: 17, weight: .bold))
                }
            }
            .frame(width: 76, height: 76)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func card(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(body).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ title: String, _ items: [String], _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color).padding(.top, 2)
                    Text(item).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func localFacts(_ s: ChatStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ON THIS MAC").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
            Text("You sent \(s.mine), they sent \(s.theirs). You opened \(s.iStarted) conversations, they opened \(s.theyStarted). "
                 + "Their median reply: \(AppModel.minutes(s.theirMedianReply)); yours: \(AppModel.minutes(s.myMedianReply))."
                 + (s.deletedByThem > 0 ? " They deleted \(s.deletedByThem) messages you'd seen." : ""))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load(force: Bool) async {
        loading = true; error = nil
        if !force, let cached = model.assistantAnalyses[chat.id.rawValue] {
            analysis = cached
            stats = await model.localStats(chat.id)
            loading = false
            return
        }
        do {
            let (a, s) = try await model.analyzeChat(chat.id)
            analysis = a; stats = s
        } catch {
            self.error = (error as? AIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func refresh() { Task { await load(force: true) } }

    private func compose() {
        let g = goal
        composing = true; composed = nil
        Task {
            do { composed = try await model.composeReply(goal: g) }
            catch { composed = (error as? AIError)?.errorDescription ?? error.localizedDescription }
            composing = false
        }
    }

    private func ask() {
        let q = question
        asking = true; answer = nil
        Task {
            do { answer = try await model.askAboutChat(q) }
            catch { answer = (error as? AIError)?.errorDescription ?? error.localizedDescription }
            asking = false
        }
    }
}

/// Simple wrapping chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.system(size: 11.5)).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.12), in: Capsule()).foregroundStyle(Theme.accent)
            }
        }
    }
}
