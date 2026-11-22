import Foundation
import OSLog

// Not thread-safe on purpose: ThermalController calls it only from its own serial queue.
nonisolated final class ThermalSampler: @unchecked Sendable {
    private let primary: () -> CPUTemperatureSource?
    private let fallback: () -> CPUTemperatureSource?
    private let fan: () -> Int?
    private var source: CPUTemperatureSource?
    private var isResolved = false

    init(
        primary: @escaping () -> CPUTemperatureSource?,
        fallback: @escaping () -> CPUTemperatureSource?,
        fan: @escaping () -> Int?
    ) {
        self.primary = primary
        self.fallback = fallback
        self.fan = fan
    }

    func sample() -> ThermalSample {
        if !isResolved {
            isResolved = true
            source = resolveSource()
        }
        return ThermalSample(celsius: source?.read(), fanPercent: fan())
    }

    private func resolveSource() -> CPUTemperatureSource? {
        if let source = primary() {
            AppLog.thermal.notice("CPU temperature from HID: \(source.sensorNames.joined(separator: ", "), privacy: .public)")
            return source
        }
        if let source = fallback() {
            AppLog.thermal.notice("CPU temperature from SMC: \(source.sensorNames.joined(separator: ", "), privacy: .public)")
            return source
        }
        AppLog.thermal.error("No CPU temperature sensors found")
        return nil
    }

    static func live() -> ThermalSampler {
        let smc = SMCConnection()
        if smc == nil { AppLog.thermal.error("AppleSMC is unavailable") }
        var fanCount: UInt32?
        return ThermalSampler(
            primary: { HIDTemperatureReader() },
            fallback: { smc.flatMap(SMCTemperatureSource.init) },
            fan: {
                guard let smc else { return nil }
                if fanCount == nil {
                    fanCount = smc.read("FNum").flatMap { SMCDecode.unsigned($0.bytes) } ?? 0
                }
                return fanPercent(smc, count: fanCount ?? 0)
            }
        )
    }

    private static func fanPercent(_ smc: SMCConnection, count: UInt32) -> Int? {
        guard count > 0 else { return nil }
        let fans = (0..<count).compactMap { n -> (actual: Double, max: Double)? in
            guard let actual = smc.read("F\(n)Ac").flatMap({ SMCDecode.float($0.bytes) }),
                  let max = smc.read("F\(n)Mx").flatMap({ SMCDecode.float($0.bytes) }) else { return nil }
            return (actual, max)
        }
        return FanSpeed.percent(fans)
    }
}
