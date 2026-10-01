//  Composer state machine.
//
//  The brief requires the composer be a formal state machine with
//  deterministic transitions, so UI state and database state cannot diverge
//  (brief §47). Representing it as an enum means an invalid state is
//  unrepresentable rather than merely unlikely.

import Foundation

/// What the composer is currently doing.
public enum ComposerState: Hashable, Sendable {
    case empty
    case typing
    case replying(to: MessageID)
    case editing(MessageID)
    case forwarding(from: ChatID, messages: [MessageID])
    case attaching
    case sending
    case failed(reason: String)
    case draftSaved
    case offlinePending

    /// Whether the user may currently type.
    public var acceptsInput: Bool {
        switch self {
        case .empty, .typing, .replying, .editing, .attaching, .draftSaved, .failed:
            return true
        case .forwarding, .sending, .offlinePending:
            return false
        }
    }

    /// Whether this state should be persisted as part of the draft.
    public var isDraftable: Bool {
        switch self {
        case .typing, .replying, .editing, .attaching, .draftSaved, .offlinePending, .failed:
            return true
        case .empty, .sending, .forwarding:
            return false
        }
    }
}
