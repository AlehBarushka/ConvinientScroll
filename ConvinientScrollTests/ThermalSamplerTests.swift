import Testing
@testable import MacToolkit

@Suite("ThermalSampler")
struct ThermalSamplerTests {
    final class FakeSource: CPUTemperatureSource {
        let sensorNames = ["fake"]
        let value: Double?

        init(_ value: Double?) { self.value = value }

        func read() -> Double? { value }
    }

    final class Counter {
        var count = 0
    }

    @Test func smcKeyDataMatchesTheKernelLayout() {
        #expect(MemoryLayout<SMCKeyData>.stride == 80)
    }

    @Test func primaryWinsAndFallbackIsNotBuilt() {
        let fallbackCalls = Counter()
        let sampler = ThermalSampler(
            primary: { FakeSource(35) },
            fallback: { fallbackCalls.count += 1; return FakeSource(20) },
            fan: { nil }
        )
        #expect(sampler.sample(includeFan: true).celsius == 35)
        #expect(fallbackCalls.count == 0)
    }

    @Test func fallbackWhenNoPrimary() {
        let sampler = ThermalSampler(primary: { nil }, fallback: { FakeSource(34) }, fan: { nil })
        #expect(sampler.sample(includeFan: true).celsius == 34)
    }

    @Test func noSourcesStillReportsFan() {
        let sampler = ThermalSampler(primary: { nil }, fallback: { nil }, fan: { 42 })
        #expect(sampler.sample(includeFan: true) == ThermalSample(celsius: nil, fanPercent: 42))
    }

    @Test func fanIsSkippedWhileTheMenuIsClosed() {
        let fanCalls = Counter()
        let sampler = ThermalSampler(
            primary: { FakeSource(35) },
            fallback: { nil },
            fan: { fanCalls.count += 1; return 42 }
        )
        #expect(sampler.sample(includeFan: false) == ThermalSample(celsius: 35, fanPercent: nil))
        #expect(fanCalls.count == 0)
    }

    @Test func sourceIsChosenOnce() {
        let primaryCalls = Counter()
        let sampler = ThermalSampler(
            primary: { primaryCalls.count += 1; return nil },
            fallback: { nil },
            fan: { nil }
        )
        _ = sampler.sample(includeFan: true)
        _ = sampler.sample(includeFan: true)
        #expect(primaryCalls.count == 1)
    }
}
