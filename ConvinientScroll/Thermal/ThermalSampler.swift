import Foundation
import OSLog

nonisolated struct ThermalSample: Equatable, Sendable {
    var celsius: Double?
    var fanPercent: Int?
}

nonisolated final class ThermalSampler {
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

    func sample(includeFan: Bool) -> ThermalSample {
        if !isResolved {
            isResolved = true
            source = resolveSource()
        }
        return ThermalSample(celsius: source?.read(), fanPercent: includeFan ? fan() : nil)
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
        var fanMaxima: [Double]?
        return ThermalSampler(
            primary: { HIDTemperatureReader() },
            fallback: { smc.flatMap(SMCTemperatureSource.init) },
            fan: {
                guard let smc else { return nil }
                let maxima = fanMaxima ?? fanMaximaReading(smc)
                if !maxima.isEmpty, !maxima.contains(0) { fanMaxima = maxima }
                let fans = maxima.enumerated().compactMap { n, max -> (actual: Double, max: Double)? in
                    smc.read("F\(n)Ac").flatMap { SMCDecode.float($0.bytes) }.map { (actual: $0, max: max) }
                }
                return FanSpeed.percent(fans)
            }
        )
    }

    private static func fanMaximaReading(_ smc: SMCConnection) -> [Double] {
        let count = smc.read("FNum").flatMap { SMCDecode.unsigned($0.bytes) } ?? 0
        return (0..<count).map { n in smc.read("F\(n)Mx").flatMap { SMCDecode.float($0.bytes) } ?? 0 }
    }
}
