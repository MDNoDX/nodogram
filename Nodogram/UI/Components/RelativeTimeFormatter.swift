//  Locale-aware, context-sensitive time formatting (brief §66).

import Foundation

public enum RelativeTimeFormatter {

    /// Chat-list timestamp: a time today, then "Yesterday", a weekday within
    /// the week, a date this year, and a full date beyond that.
    public static func short(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year(.twoDigits).month(.twoDigits).day(.twoDigits))
    }

    /// The precise value, for tooltips.
    public static func exact(_ date: Date) -> String {
        date.formatted(date: .complete, time: .standard)
    }

    /// "today at 14:32", "yesterday at 09:10", "on 24 Sep at 18:00".
    public static func readTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) { return "today at \(time)" }
        if calendar.isDateInYesterday(date) { return "yesterday at \(time)" }
        return "on \(date.formatted(.dateTime.day().month(.abbreviated))) at \(time)"
    }
}
