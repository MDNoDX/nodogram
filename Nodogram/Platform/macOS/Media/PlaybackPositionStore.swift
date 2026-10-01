//  Remembers where playback stopped, per video, across launches.
//
//  Keyed by Telegram's remote unique id, which is stable across sessions (the
//  numeric file id is not). Bounded, so it cannot grow forever.

import Foundation

public enum PlaybackPositionStore {
    private static let key = "playback.positions"
    private static let limit = 400

    private struct Entry: Codable {
        var seconds: Double
        var updated: Date
    }

    /// A position worth resuming from: not the first few seconds, and not the
    /// very end (which means "watched", not "paused").
    public static func resumePosition(for uniqueID: String, duration: Double) -> Double? {
        guard let entry = load()[uniqueID], entry.seconds > 5 else { return nil }
        if duration > 0, entry.seconds > duration - 5 { return nil }
        return entry.seconds
    }

    public static func save(_ seconds: Double, for uniqueID: String, duration: Double) {
        guard !uniqueID.isEmpty, seconds.isFinite else { return }
        var entries = load()
        if duration > 0, seconds > duration - 5 {
            entries.removeValue(forKey: uniqueID)   // finished: start over next time
        } else if seconds > 5 {
            entries[uniqueID] = Entry(seconds: seconds, updated: Date())
        }
        if entries.count > limit {
            let oldest = entries.sorted { $0.value.updated < $1.value.updated }.prefix(entries.count - limit)
            for (id, _) in oldest { entries.removeValue(forKey: id) }
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }
}
