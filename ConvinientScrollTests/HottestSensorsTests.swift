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
        sensors.recordFullScan([30, 41, -9201, 39, .nan, 45, ].enumerated().map { ($0.offset, $0.element) })

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

    @Test func fewerSensorsThanTheSubsetReadsThemAll() {
        var sensors = HottestSensors(count: 2)
        _ = sensors.nextIndices()
        sensors.recordFullScan([(0, 30), (1, 31)])
        #expect(sensors.nextIndices() == [0, 1])
    }
}
