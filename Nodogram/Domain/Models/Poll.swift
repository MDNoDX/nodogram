//  Polls and quizzes.
//
//  Telegram's poll model has rules that are easy to get subtly wrong in a UI —
//  results that stay hidden until you vote or until the poll closes, revoting
//  that a poll may forbid, quizzes with more than one correct answer — so they
//  live here as plain logic, tested without a window.

import Foundation

public struct PollContent: Hashable, Sendable {

    public struct Option: Hashable, Sendable, Identifiable {
        /// Position in Telegram's option list — what a vote refers to. Distinct
        /// from display order, which a poll may shuffle.
        public let index: Int
        public let text: String
        public let entities: [TextEntity]
        public let voterCount: Int
        /// Telegram's own rounding, so percentages always add up the way the
        /// official apps show them.
        public let percentage: Int
        public let isChosen: Bool
        /// The vote is being sent; shown as in-progress, not yet as chosen.
        public let isBeingChosen: Bool
        /// Label for media attached to the option ("Photo"), if any.
        public let mediaLabel: String?

        public var id: Int { index }

        public init(index: Int, text: String, entities: [TextEntity] = [], voterCount: Int = 0,
                    percentage: Int = 0, isChosen: Bool = false, isBeingChosen: Bool = false,
                    mediaLabel: String? = nil) {
            self.index = index; self.text = text; self.entities = entities
            self.voterCount = voterCount; self.percentage = percentage
            self.isChosen = isChosen; self.isBeingChosen = isBeingChosen; self.mediaLabel = mediaLabel
        }
    }

    public enum Kind: Hashable, Sendable {
        case regular
        /// `correct` holds option indexes; Telegram allows more than one.
        /// It is empty until the user has answered.
        case quiz(correct: Set<Int>, explanation: String)
    }

    public enum Restriction: Hashable, Sendable {
        case closed, notYetSent, scheduled, country, membership, other

        public var explanation: String {
            switch self {
            case .closed: return "This poll is closed."
            case .notYetSent: return "This poll hasn't been sent yet."
            case .scheduled: return "This poll is scheduled and can't be voted in yet."
            case .country: return "Voting isn't available in your country."
            case .membership: return "You need to be a member of this chat for a day before voting."
            case .other: return "You can't vote in this poll."
            }
        }
    }

    /// How a single option should look once results are visible.
    public enum OptionState: Hashable, Sendable {
        case neutral
        case chosen
        case correct          // quiz: right answer, chosen
        case wrong            // quiz: chosen, but not right
        case missedCorrect    // quiz: right answer the user did not pick
    }

    public let id: Int64
    public let question: String
    public let questionEntities: [TextEntity]
    public let details: String
    /// In display order.
    public let options: [Option]
    public let totalVoters: Int
    public let isAnonymous: Bool
    public let allowsMultipleAnswers: Bool
    public let allowsRevoting: Bool
    /// Whether Telegram will show this user the results right now. It is false
    /// before the user votes (verified on 25 real polls), and stays false after
    /// voting only when the creator hid results until the poll closes.
    public let canSeeResults: Bool
    public let isClosed: Bool
    public let closeDate: Date?
    public let kind: Kind
    public let restriction: Restriction?

    public init(id: Int64, question: String, questionEntities: [TextEntity] = [], details: String = "",
                options: [Option], totalVoters: Int = 0, isAnonymous: Bool = true,
                allowsMultipleAnswers: Bool = false, allowsRevoting: Bool = true, canSeeResults: Bool = true,
                isClosed: Bool = false, closeDate: Date? = nil, kind: Kind = .regular,
                restriction: Restriction? = nil) {
        self.id = id; self.question = question; self.questionEntities = questionEntities
        self.details = details; self.options = options; self.totalVoters = totalVoters
        self.isAnonymous = isAnonymous; self.allowsMultipleAnswers = allowsMultipleAnswers
        self.allowsRevoting = allowsRevoting; self.canSeeResults = canSeeResults
        self.isClosed = isClosed; self.closeDate = closeDate; self.kind = kind
        self.restriction = restriction
    }

    public var isQuiz: Bool {
        if case .quiz = kind { return true }
        return false
    }

    public var hasVoted: Bool { options.contains { $0.isChosen } }
    public var isVoting: Bool { options.contains { $0.isBeingChosen } }

    /// Results (bars and percentages) appear once the user has voted or the
    /// poll is closed — and never when the creator hid them.
    public var showsResults: Bool {
        (hasVoted || isClosed) && canSeeResults
    }

    public var canVote: Bool {
        !isClosed && restriction == nil && !hasVoted && !isVoting
    }

    /// Quizzes are final; regular polls allow taking a vote back unless the
    /// creator turned revoting off.
    public var canRetractVote: Bool {
        hasVoted && !isClosed && !isQuiz && allowsRevoting && restriction == nil
    }

    public func state(of option: Option) -> OptionState {
        guard case .quiz(let correct, _) = kind, !correct.isEmpty else {
            return option.isChosen ? .chosen : .neutral
        }
        let isCorrect = correct.contains(option.index)
        switch (option.isChosen, isCorrect) {
        case (true, true): return .correct
        case (true, false): return .wrong
        case (false, true): return .missedCorrect
        case (false, false): return .neutral
        }
    }

    /// "Anonymous Quiz", "Public Poll", "Final results"…
    public var title: String {
        if isClosed { return "Final results" }
        let visibility = isAnonymous ? "Anonymous" : "Public"
        return "\(visibility) \(isQuiz ? "Quiz" : "Poll")"
    }

    /// "1 vote", "1,234 votes", "No votes yet"; "answer" wording for quizzes.
    public var votesSummary: String {
        let noun = isQuiz ? "answer" : "vote"
        if totalVoters == 0 { return "No \(noun)s yet" }
        let count = totalVoters.formatted(.number)
        return "\(count) \(noun)\(totalVoters == 1 ? "" : "s")"
    }
}
