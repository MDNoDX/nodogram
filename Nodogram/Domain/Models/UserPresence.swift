//  Online / last-seen state for a person.
//
//  Mirrors Telegram's own granularity. "Recently", "within a week" and "within a
//  month" are deliberately vague on Telegram's side — they are what a user sees
//  when the other person hides their exact last-seen time — so they are kept
//  vague here rather than turned into a fake precise time.

import Foundation

public enum UserPresence: Hashable, Sendable {
    case online
    case lastSeen(Date)
    case recently
    case withinWeek
    case withinMonth
    case longAgo
}
