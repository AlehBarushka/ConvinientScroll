import Testing
@testable import MacToolkit

@Suite("MenuBarSegment")
@MainActor
struct MenuBarSegmentTests {
    @Test func memorySegment() {
        let display = MemoryMonitor.Display(percent: 54, pressure: .warning)
        #expect(display.segment == MenuBarSegment(
            symbol: "memorychip", text: "54%", reservedCharacters: 4, tint: .warning,
            accessibility: "54% memory used, pressure warning"
        ))
    }

    @Test func memorySegmentWithoutValue() {
        let segment = MemoryMonitor.Display(percent: nil, pressure: .normal).segment
        #expect(segment.text == "—%")
        #expect(segment.accessibility == "—% memory used, pressure normal")
    }

    @Test func thermalSegment() {
        let display = ThermalMonitor.Display(celsius: 62, level: .heavy)
        #expect(display.segment == MenuBarSegment(
            symbol: "thermometer.medium", text: "62°", reservedCharacters: 4, tint: .warning,
            accessibility: "CPU 62°, thermal pressure heavy"
        ))
    }

    @Test func thermalSegmentWithoutValue() {
        let segment = ThermalMonitor.Display(celsius: nil, level: nil).segment
        #expect(segment.text == "—°")
        #expect(segment.tint == .none)
        #expect(segment.accessibility == "CPU —°, thermal pressure unknown")
    }

    @Test func memoryPressureTint() {
        #expect([MemoryPressure.normal, .warning, .critical].map(\.tint) == [.none, .warning, .critical])
    }
}
