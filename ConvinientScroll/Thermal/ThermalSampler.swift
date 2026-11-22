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
        guard let source = primary() ?? fallback() else {
            AppLog.thermal.error("No CPU temperature sensors found")
            return nil
        }
        let names = source.sensorNames.joined(separator: ", ")
        AppLog.thermal.notice("CPU temperature from \(String(describing: type(of: source)), privacy: .public): \(names, privacy: .public)")
        return source
    }

    static func live() -> ThermalSampler {
        let smc = SMCConnection()
        if smc == nil { AppLog.thermal.error("AppleSMC is unavailable") }
        var fanMaxima: [Double]?
        return ThermalSampler(
            primary: { smc.flatMap(SMCTemperatureSource.init) },
            fallback: { HIDTemperatureReader() },
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
