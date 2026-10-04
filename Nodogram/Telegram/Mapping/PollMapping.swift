//  TDLib polls → PollContent.

import Foundation
import NodogramDomain
import TDLibKit

/// TDLibKit also declares a `Date` type; in this file `Date` means Foundation's.
private typealias Date = Foundation.Date

enum PollMapping {

    static func map(_ message: MessagePoll) -> PollContent {
        map(message.poll, details: message.description.text)
    }

    /// `details` (the poll's description) only arrives with the message, not
    /// with `updatePoll`, so live updates pass it through from what is known.
    static func map(_ poll: Poll, details: String) -> PollContent {
        let options = poll.options.enumerated().map { index, option in
            PollContent.Option(
                index: index,
                text: option.text.text,
                entities: MediaMapping.entities(option.text),
                voterCount: option.voterCount,
                percentage: option.votePercentage,
                isChosen: option.isChosen,
                isBeingChosen: option.isBeingChosen,
                mediaLabel: option.media.map(mediaLabel))
        }

        // A poll may display its options in a shuffled order; votes still refer
        // to the original positions, which `Option.index` keeps.
        let displayed: [PollContent.Option] = {
            let order = poll.optionOrder.filter { options.indices.contains($0) }
            guard order.count == options.count else { return options }
            return order.map { options[$0] }
        }()

        let kind: PollContent.Kind
        switch poll.type {
        case .pollTypeRegular:
            kind = .regular
        case .pollTypeQuiz(let quiz):
            kind = .quiz(correct: Set(quiz.correctOptionIds), explanation: quiz.explanation.text)
        }

        return PollContent(
            id: poll.id.rawValue,
            question: poll.question.text,
            questionEntities: MediaMapping.entities(poll.question),
            details: details,
            options: displayed,
            totalVoters: poll.totalVoterCount,
            isAnonymous: poll.isAnonymous,
            allowsMultipleAnswers: poll.allowsMultipleAnswers,
            allowsRevoting: poll.allowsRevoting,
            canSeeResults: poll.canSeeResults,
            isClosed: poll.isClosed,
            closeDate: poll.closeDate > 0 ? Date(timeIntervalSince1970: TimeInterval(poll.closeDate)) : nil,
            kind: kind,
            restriction: poll.voteRestrictionReason.map(restriction))
    }

    private static func restriction(_ reason: PollVoteRestrictionReason) -> PollContent.Restriction {
        switch reason {
        case .pollVoteRestrictionReasonClosed: return .closed
        case .pollVoteRestrictionReasonYetUnsent: return .notYetSent
        case .pollVoteRestrictionReasonScheduled: return .scheduled
        case .pollVoteRestrictionReasonCountryRestricted: return .country
        case .pollVoteRestrictionReasonMembershipRequired: return .membership
        case .pollVoteRestrictionReasonOther: return .other
        }
    }

    private static func mediaLabel(_ media: TDLibKit.PollMedia) -> String {
        switch media {
        case .pollMediaPhoto: return "Photo"
        case .pollMediaVideo: return "Video"
        case .pollMediaAnimation: return "GIF"
        case .pollMediaAudio: return "Audio"
        case .pollMediaDocument: return "File"
        case .pollMediaSticker: return "Sticker"
        case .pollMediaLocation, .pollMediaVenue: return "Location"
        case .pollMediaLink: return "Link"
        }
    }
}
