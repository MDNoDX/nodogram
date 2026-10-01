//  Connection state, shown unobtrusively (brief §28).

import Foundation

public enum ConnectionState: Hashable, Sendable {
    case connected
    case connecting
    case connectingToProxy
    case updating
    case offline

    /// Whether to surface this at all. A healthy connection needs no indicator;
    /// the brief asks for no distracting banners.
    public var isWorthShowing: Bool {
        self != .connected
    }
}
