import Testing
@testable import MacToolkit

@Suite("ThermalLevel")
struct ThermalLevelTests {
    @Test func rawStatesMapToLevels() {
        #expect([0, 1, 2, 3, 4].map { ThermalLevel(rawState: $0) } == [.nominal, .moderate, .heavy, .critical, .critical])
        #expect(ThermalLevel(rawState: 5) == nil)
    }

    @Test func onlyHeavyAndCriticalThrottle() {
        #expect(ThermalLevel.allCases.filter(\.isThrottling) == [.heavy, .critical])
    }

    @Test func tintFollowsLevel() {
        #expect(ThermalLevel.allCases.map(\.tint) == [.none, .none, .warning, .critical])
    }

    @Test func menuBarText() {
        #expect(ThermalText.menuBar(celsius: 58) == "58°")
        #expect(ThermalText.menuBar(celsius: nil) == "—°")
    }

    @Test func detailText() {
        #expect(ThermalText.detail(celsius: 58, fanPercent: 42, level: .nominal) == "CPU 58° · Fan 42% · Nominal")
        #expect(ThermalText.detail(celsius: 58, fanPercent: nil, level: .heavy) == "CPU 58° · Heavy")
        #expect(ThermalText.detail(celsius: nil, fanPercent: nil, level: nil) == "CPU —° · —")
    }

    @Test func durationText() {
        #expect(ThermalText.duration(42) == "42s")
        #expect(ThermalText.duration(4 * 60 + 10) == "4m")
        #expect(ThermalText.duration(112 * 60) == "1h 52m")
    }
}
