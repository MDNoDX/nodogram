//  Polls and quizzes inside a message bubble.
//
//  Before voting: radio buttons (or checkboxes for multiple answers); a single
//  click votes. After voting, or once closed: percentage, bar and the user's
//  choice — and for quizzes, which answers were right. Results the creator
//  chose to hide stay hidden.

import SwiftUI
import NodogramDomain
import NodogramUI

public struct PollView: View {
    let poll: PollContent
    let isOutgoing: Bool
    let onVote: ([Int]) -> Void
    let onRetract: () -> Void

    /// Pending picks in a multiple-answer poll, before "Vote" is pressed.
    @State private var selection: Set<Int> = []
    @State private var showsExplanation = false
    @State private var revealResults = false

    public init(poll: PollContent, isOutgoing: Bool,
                onVote: @escaping ([Int]) -> Void, onRetract: @escaping () -> Void) {
        self.poll = poll
        self.isOutgoing = isOutgoing
        self.onVote = onVote
        self.onRetract = onRetract
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: poll.showsResults ? 9 : 2) {
                ForEach(poll.options) { option in
                    if poll.showsResults {
                        ResultRow(option: option, state: poll.state(of: option), reveal: revealResults)
                    } else {
                        ChoiceRow(
                            option: option,
                            isMultiple: poll.allowsMultipleAnswers,
                            isSelected: selection.contains(option.index),
                            isEnabled: poll.canVote
                        ) { tap(option) }
                    }
                }
            }

            footer
        }
        .frame(minWidth: 280, idealWidth: 330, maxWidth: 380, alignment: .leading)
        .onAppear { revealResults = poll.showsResults }
        .onChange(of: poll.showsResults) { _, shows in
            withAnimation(.easeOut(duration: 0.45)) { revealResults = shows }
        }
        .onChange(of: poll.hasVoted) { _, voted in
            if voted { selection = [] }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: poll.isQuiz ? "graduationcap.fill" : "chart.bar.fill")
                    .font(.system(size: 10))
                Text(poll.title)
                if poll.allowsMultipleAnswers, !poll.isClosed {
                    Text("· multiple answers")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)

            Text(FormattedText.attributed(poll.question, entities: poll.questionEntities, baseSize: 14))
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !poll.details.isEmpty {
                Text(poll.details)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(poll.votesSummary)
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)

            if let closeDate = poll.closeDate, !poll.isClosed {
                Text("· closes \(closeDate.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if case .quiz(_, let explanation) = poll.kind, poll.hasVoted || poll.isClosed, !explanation.isEmpty {
                Button {
                    showsExplanation.toggle()
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Explanation")
                .popover(isPresented: $showsExplanation, arrowEdge: .bottom) {
                    Text(explanation)
                        .font(.system(size: 12.5))
                        .frame(maxWidth: 300, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                }
            }

            if poll.allowsMultipleAnswers, poll.canVote, !selection.isEmpty {
                Button("Vote") {
                    onVote(selection.sorted())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            } else if poll.canRetractVote {
                Button("Retract vote", action: onRetract)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.accent)
            } else if poll.hasVoted, !poll.canSeeResults, !poll.isClosed {
                Text("Results after the poll closes")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let restriction = poll.restriction, restriction != .closed, !poll.hasVoted {
                Label(restriction.explanation, systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .offset(y: 18)
            }
        }
        .padding(.bottom, poll.restriction != nil && poll.restriction != .closed && !poll.hasVoted ? 16 : 0)
    }

    private func tap(_ option: PollContent.Option) {
        guard poll.canVote else { return }
        if poll.allowsMultipleAnswers {
            if selection.contains(option.index) { selection.remove(option.index) } else { selection.insert(option.index) }
        } else {
            onVote([option.index])
        }
    }
}

// MARK: - Rows

/// An option before results are visible: a radio button (or checkbox).
private struct ChoiceRow: View {
    let option: PollContent.Option
    let isMultiple: Bool
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                ZStack {
                    if option.isBeingChosen {
                        ProgressView().controlSize(.mini)
                    } else if isMultiple {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? Theme.accent : Color.secondary.opacity(0.55), lineWidth: 1.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Theme.accent : .clear))
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                    } else {
                        Circle().strokeBorder(Color.secondary.opacity(0.55), lineWidth: 1.5)
                    }
                }
                .frame(width: 17, height: 17)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4.5 }

                VStack(alignment: .leading, spacing: 2) {
                    Text(FormattedText.attributed(option.text, entities: option.entities, baseSize: 13.5))
                        .font(.system(size: 13.5))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let media = option.mediaLabel {
                        Label(media, systemImage: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered && isEnabled ? Theme.accent.opacity(0.09) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel(option.text)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// An option once results are visible: percentage, text, bar.
private struct ResultRow: View {
    let option: PollContent.Option
    let state: PollContent.OptionState
    /// Animates bars from zero the moment results first appear.
    let reveal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(option.percentage)%")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .frame(minWidth: 38, alignment: .trailing)

                Text(FormattedText.attributed(option.text, entities: option.entities, baseSize: 13.5))
                    .font(.system(size: 13.5))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if let mark = mark {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mark.color)
                        .accessibilityLabel(mark.label)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.13))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(5, geometry.size.width * CGFloat(reveal ? option.percentage : 0) / 100))
                }
            }
            .frame(height: 5)
            .padding(.leading, 46)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(option.text), \(option.percentage) percent, \(option.voterCount) votes")
    }

    private var barColor: Color {
        switch state {
        case .correct, .missedCorrect: return Theme.success
        case .wrong: return Theme.failure
        case .chosen: return Theme.accent
        case .neutral: return Theme.accent.opacity(0.55)
        }
    }

    /// Never colour alone: every judged state also has a symbol.
    private var mark: (symbol: String, color: Color, label: String)? {
        switch state {
        case .chosen: return ("checkmark.circle.fill", Theme.accent, "Your vote")
        case .correct: return ("checkmark.circle.fill", Theme.success, "Correct, your answer")
        case .wrong: return ("xmark.circle.fill", Theme.failure, "Wrong, your answer")
        case .missedCorrect: return ("checkmark.circle", Theme.success, "Correct answer")
        case .neutral: return nil
        }
    }
}
