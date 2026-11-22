import Foundation
import OSLog
import notify

final class ThermalPressureSource {
    private static let name = "com.apple.system.thermalpressurelevel"

    private var token: Int32?

    func start(onChange: @escaping (ThermalLevel?) -> Void) {
        stop()
        var token: Int32 = 0
        let status = notify_register_dispatch(Self.name, &token, .main) { token in
            MainActor.assumeIsolated { onChange(Self.level(token)) }
        }
        guard status == NOTIFY_STATUS_OK else {
            AppLog.thermal.error("Thermal pressure notifications are unavailable: \(status)")
            return
        }
        self.token = token
    }

    func current() -> ThermalLevel? {
        token.flatMap(Self.level)
    }

    func stop() {
        guard let token else { return }
        notify_cancel(token)
        self.token = nil
    }

    private nonisolated static func level(_ token: Int32) -> ThermalLevel? {
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return nil }
        return ThermalLevel(rawState: state)
    }
}
