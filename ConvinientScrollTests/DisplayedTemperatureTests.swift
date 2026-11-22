import Testing
@testable import MacToolkit

@Suite("DisplayedTemperature")
struct DisplayedTemperatureTests {
    @Test func firstReadingShowsAtOnce() {
        var shown = DisplayedTemperature()
        #expect(shown.update(34.9) == 35)
    }

    @Test func jitterUnderTheDeadZoneKeepsTheNumber() {
        var shown = DisplayedTemperature()
        _ = shown.update(35)
        #expect([35.2, 36.4, 34.6, 36.0].map { shown.update($0) } == [35, 35, 35, 35])
    }

    @Test func singleSpikeIsNotShown() {
        var shown = DisplayedTemperature()
        _ = shown.update(35)
        _ = shown.update(35)
        #expect(shown.update(41) == 35)
        #expect(shown.update(35) == 35)
    }

    @Test func sustainedRiseIsShown() {
        var shown = DisplayedTemperature()
        _ = shown.update(35)
        #expect([38, 38, 38].map { shown.update($0) } == [35, 38, 38])
    }

    @Test func noReadingShowsNothingAndStartsOver() {
        var shown = DisplayedTemperature()
        _ = shown.update(35)
        #expect(shown.update(nil) == nil)
        #expect(shown.update(50) == 50)
    }

    @Test func resetShowsTheNextReadingAtOnce() {
        var shown = DisplayedTemperature()
        _ = shown.update(35)
        _ = shown.update(35)
        shown.reset()
        #expect(shown.update(36) == 36)
    }
}
