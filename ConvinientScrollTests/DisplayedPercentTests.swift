import Testing
@testable import MacToolkit

@Suite("DisplayedPercent")
struct DisplayedPercentTests {
    @Test func firstReadingShowsAtOnce() {
        var shown = DisplayedPercent()
        #expect(shown.update(70.4) == 70)
    }

    @Test func jitterAcrossTheRoundingBoundaryKeepsTheNumber() {
        var shown = DisplayedPercent()
        _ = shown.update(70.4)
        #expect([70.6, 70.4, 70.9, 70.5].map { shown.update($0) } == [70, 70, 70, 70])
    }

    @Test func aFullPointChangesTheNumber() {
        var shown = DisplayedPercent()
        _ = shown.update(70.4)
        #expect(shown.update(71.2) == 71)
        #expect(shown.update(70.4) == 71)
        #expect(shown.update(69.9) == 70)
    }

    @Test func resetShowsTheNextReadingAtOnce() {
        var shown = DisplayedPercent()
        _ = shown.update(70.4)
        shown.reset()
        #expect(shown.update(70.6) == 71)
    }

    @Test func staysWithinZeroToHundred() {
        var shown = DisplayedPercent()
        #expect(shown.update(100.4) == 100)
        shown.reset()
        #expect(shown.update(-0.4) == 0)
    }
}
