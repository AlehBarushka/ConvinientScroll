import Foundation
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            lastError = error.localizedDescription
        }
    }
}

