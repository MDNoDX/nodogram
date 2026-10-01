//  Human wording for online / last-seen state.
//
//  Telegram's vague states ("recently", "within a week") are what a user sees
//  when the other person hides their exact time, so they stay vague here.

import Foundation
import NodogramDomain

public enum PresenceFormatter {
    public static func describe(_ presence: UserPresence?, now: Date = Date()) -> String? {
        guard let presence else { return nil }
        switch presence {
        case .online:
            return "online"
        case .recently:
            return "last seen recently"
        case .withinWeek:
            return "last seen within a week"
        case .withinMonth:
            return "last seen within a month"
        case .longAgo:
            return "last seen a long time ago"
        case .lastSeen(let date):
            let calendar = Calendar.current
            let time = date.formatted(.dateTime.hour().minute())
            let elapsed = now.timeIntervalSince(date)
            if elapsed < 60 { return "last seen just now" }
            if elapsed < 3600 {
                let minutes = Int(elapsed / 60)
                return "last seen \(minutes) minute\(minutes == 1 ? "" : "s") ago"
            }
            if calendar.isDateInToday(date) { return "last seen today at \(time)" }
            if calendar.isDateInYesterday(date) { return "last seen yesterday at \(time)" }
            return "last seen \(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
        }
    }
}
