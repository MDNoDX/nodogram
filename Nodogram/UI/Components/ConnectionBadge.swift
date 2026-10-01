//  Unobtrusive connection indicator.
//
//  The brief asks for subtle states and explicitly no constant banners
//  (brief §28), so a healthy connection renders nothing at all.

import SwiftUI
import NodogramDomain

public struct ConnectionBadge: View {
    private let state: ConnectionState

    public init(state: ConnectionState) {
        self.state = state
    }

    private var label: String {
        switch state {
        case .connected: return L10n.connected
        case .connecting: return L10n.connecting
        case .connectingToProxy: return L10n.connecting
        case .updating: return L10n.updating
        case .offline: return L10n.offline
        }
    }

    /// Paired with the text label, so state is never conveyed by colour alone.
    private var icon: String {
        switch state {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .connectingToProxy: return "arrow.triangle.2.circlepath"
        case .updating: return "arrow.down.circle"
        case .offline: return "wifi.slash"
        }
    }

    private var tint: Color {
        switch state {
        case .connected: return Theme.success
        case .connecting, .connectingToProxy, .updating: return Theme.warning
        case .offline: return Theme.failure
        }
    }

    public var body: some View {
        if state.isWorthShowing {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(Theme.Typography.timestamp)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.1), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
        }
    }
}
