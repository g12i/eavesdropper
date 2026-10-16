import AppKit
import OSLog
import ServiceManagement

/// Login item via `SMAppService.mainApp`. The system persists the registration, so its status is the
/// single source of truth (also reflects the user toggling it in System Settings → Login Items).
@MainActor
enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user must allow it in System Settings → General → Login Items.
        case requiresApproval
    }

    private static let logger = Logger(subsystem: "com.tapscribe.app", category: "LaunchAtLogin")

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notRegistered, .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }

    /// Flips the registration; returns an error message suitable for an alert on failure.
    static func toggle() -> String? {
        let service = SMAppService.mainApp
        do {
            switch state {
            case .enabled, .requiresApproval:
                try service.unregister()
            case .disabled:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            return nil
        } catch {
            logger.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
