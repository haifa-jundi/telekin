import ServiceManagement

/// "Open at login", through the system's Login Items list (System Settings › General › Login Items).
/// The system stores the choice, so it never goes into Telekin's own settings.
enum LoginItem {
    enum State: Equatable {
        case on
        case off
        /// Registered, but the user has to allow it in System Settings first.
        case needsApproval
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// Turns opening at login on or off. Returns a message to show when the system refuses.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if on {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return nil
        } catch {
            return "Couldn't change Open at login: \(error.localizedDescription)"
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
