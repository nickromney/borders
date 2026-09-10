import BordersCore
import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    private(set) var isEnabled = false
    private(set) var requiresApproval = false
    private(set) var errorMessage: String?

    var canManageLaunchAtLogin: Bool {
        LaunchEligibility.canManageLaunchAtLogin(bundleURL: Bundle.main.bundleURL)
    }

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard canManageLaunchAtLogin else { return }
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Could not change Open at Login. \(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() {
        guard canManageLaunchAtLogin else { return }
        let status = SMAppService.mainApp.status
        requiresApproval = status == .requiresApproval
        isEnabled = status == .enabled || requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
