import Testing
import Foundation
@testable import NodogramDomain

@Suite("PollContent")
struct PollContentTests {

    private func poll(chosen: Set<Int> = [], closed: Bool = false, canSeeResults: Bool = true,
                      kind: PollContent.Kind = .regular, allowsRevoting: Bool = true,
                      restriction: PollContent.Restriction? = nil) -> PollContent {
        PollContent(
            id: 1, question: "Lunch?",
            options: (0..<3).map { PollContent.Option(index: $0, text: "Option \($0)", isChosen: chosen.contains($0)) },
            totalVoters: 10, allowsRevoting: allowsRevoting, canSeeResults: canSeeResults,
            isClosed: closed, kind: kind, restriction: restriction)
    }

    @Test("Results stay hidden until the user votes")
    func resultsHiddenBeforeVoting() {
        #expect(!poll().showsResults)
        #expect(poll(chosen: [1]).showsResults)
    }

    @Test("A closed poll shows results even without a vote")
    func closedPollShowsResults() {
        #expect(poll(closed: true).showsResults)
        #expect(!poll(closed: true).canVote)
    }

    @Test("Results hidden by the creator stay hidden even after voting")
    func creatorHiddenResults() {
        #expect(!poll(chosen: [0], canSeeResults: false).showsResults)
    }

    @Test("Voting is blocked by any restriction")
    func restrictionsBlockVoting() {
        #expect(poll().canVote)
        #expect(!poll(restriction: .membership).canVote)
        #expect(!poll(chosen: [0]).canVote)
    }

    @Test("Votes can be retracted in regular polls only, and only if revoting is allowed")
    func retracting() {
        #expect(poll(chosen: [0]).canRetractVote)
        #expect(!poll(chosen: [0], allowsRevoting: false).canRetractVote)
        #expect(!poll(chosen: [0], kind: .quiz(correct: [1], explanation: "")).canRetractVote)
        #expect(!poll(chosen: [0], closed: true).canRetractVote)
    }

    @Test("Quiz options are judged right, wrong or missed")
    func quizStates() {
        let quiz = poll(chosen: [0], kind: .quiz(correct: [1], explanation: "Because."))
        #expect(quiz.state(of: quiz.options[0]) == .wrong)
        #expect(quiz.state(of: quiz.options[1]) == .missedCorrect)
        #expect(quiz.state(of: quiz.options[2]) == .neutral)
    }

    @Test("A quiz may have several correct answers")
    func multipleCorrect() {
        let quiz = poll(chosen: [0, 2], kind: .quiz(correct: [0, 2], explanation: ""))
        #expect(quiz.state(of: quiz.options[0]) == .correct)
        #expect(quiz.state(of: quiz.options[2]) == .correct)
    }

    @Test("Titles and vote counts read naturally")
    func wording() {
        #expect(poll().title == "Anonymous Poll")
        #expect(poll(kind: .quiz(correct: [], explanation: "")).title == "Anonymous Quiz")
        #expect(poll(closed: true).title == "Final results")
        #expect(poll().votesSummary == "10 votes")
        #expect(poll(kind: .quiz(correct: [], explanation: "")).votesSummary == "10 answers")
    }
}
