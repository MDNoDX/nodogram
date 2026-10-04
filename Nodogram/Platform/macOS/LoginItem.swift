//  Start Nodogram when the user logs in, so it is already receiving updates.

import Foundation
import ServiceManagement

public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS may ask the user to approve this in System Settings → Login Items.
    public static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    public static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
