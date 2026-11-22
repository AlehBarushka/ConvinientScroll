import Testing
@testable import MacToolkit

@Suite("HottestSensors")
struct HottestSensorsTests {
    @Test func firstSampleReadsEverySensor() {
        var sensors = HottestSensors(count: 6)
        #expect(sensors.nextIndices() == [0, 1, 2, 3, 4, 5])
    }

    @Test func keepsTheFourHottestUntilTheRescan() {
        var sensors = HottestSensors(count: 6)
        _ = sensors.nextIndices()
        sensors.recordFullScan([30, 41, -9201, 39, .nan, 45].enumerated().map { ($0.offset, $0.element) })

        for _ in 1..<HottestSensors.rescanEvery {
            #expect(sensors.nextIndices() == [0, 1, 3, 5])
        }
        #expect(sensors.nextIndices() == [0, 1, 2, 3, 4, 5])
    }

    @Test func onlyGarbageKeepsReadingEverySensor() {
        var sensors = HottestSensors(count: 3)
        _ = sensors.nextIndices()
        sensors.recordFullScan([(0, -9201), (1, .nan), (2, 0)])
        #expect(sensors.nextIndices() == [0, 1, 2])
        #expect(sensors.isFullScan)
    }

    @Test func invalidateForcesAFullScanAtOnce() {
        var sensors = HottestSensors(count: 6)
        _ = sensors.nextIndices()
        sensors.recordFullScan([(0, 30), (1, 41), (3, 39), (5, 45)])
        #expect(sensors.nextIndices() == [0, 1, 3, 5])

        sensors.invalidate()
        #expect(sensors.nextIndices() == [0, 1, 2, 3, 4, 5])
        #expect(sensors.isFullScan)
    }

    @Test func readReturnsTheHottestAndThenReadsOnlyTheHotOnes() {
        var sensors = HottestSensors(count: 6)
        var values: [Double] = [30, 41, 35, 39, 33, 45]
        var asked: [Int] = []
        let read = { (index: Int) -> Double? in asked.append(index); return values[index] }

        #expect(sensors.read(using: read) == 45)
        #expect(asked == [0, 1, 2, 3, 4, 5])

        asked = []
        values[5] = 44
        #expect(sensors.read(using: read) == 44)
        #expect(asked == [1, 2, 3, 5])
    }

    @Test func garbageFromTheHotOnesRescansEverySensorAtOnce() {
        var sensors = HottestSensors(count: 6)
        var values: [Double?] = [30, 41, 35, 39, 33, 45]
        _ = sensors.read { values[$0] }

        for index in [1, 2, 3, 5] { values[index] = -9201 }
        #expect(sensors.read { values[$0] } == 33)
    }

    @Test func noReadableSensorGivesNothing() {
        var sensors = HottestSensors(count: 3)
        #expect(sensors.read { _ in nil } == nil)
    }

    @Test func fewerSensorsThanTheSubsetReadsThemAll() {
        var sensors = HottestSensors(count: 2)
        _ = sensors.nextIndices()
        sensors.recordFullScan([(0, 30), (1, 31)])
        #expect(sensors.nextIndices() == [0, 1])
    }
}
