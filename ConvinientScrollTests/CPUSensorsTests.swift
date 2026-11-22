import Testing
@testable import MacToolkit

@Suite("CPUSensors")
struct CPUSensorsTests {
    @Test func namesFromM1ToM5AreCPUDie() {
        for name in ["PMU tdie1", "PMU2 tdie10", "pACC MTR Temp Sensor0", "eACC MTR Temp Sensor1", "SOC MTR Temp Sensor2"] {
            #expect(CPUSensors.isCPUDie(name: name), "\(name)")
        }
    }

    @Test func calibrationBatteryAndStorageAreNot() {
        for name in ["PMU tcal", "PMU2 tcal", "gas gauge battery", "NAND CH0 temp", "PMU tdev1"] {
            #expect(!CPUSensors.isCPUDie(name: name), "\(name)")
        }
    }

    @Test func hottestSkipsGarbage() {
        let readings = [
            SensorReading(name: "a", celsius: 34.9),
            SensorReading(name: "b", celsius: -9201.14),
            SensorReading(name: "c", celsius: .nan),
            SensorReading(name: "d", celsius: 31.6)
        ]
        #expect(CPUSensors.hottest(readings) == 34.9)
    }

    @Test func onlyGarbageGivesNoTemperature() {
        let readings = [
            SensorReading(name: "a", celsius: -9201.14),
            SensorReading(name: "b", celsius: 0),
            SensorReading(name: "c", celsius: .nan)
        ]
        #expect(CPUSensors.hottest(readings) == nil)
        #expect(CPUSensors.hottest([]) == nil)
    }

    @Test func smcCPUKeys() {
        #expect(CPUSensors.isCPUKey("Tp00", type: "flt "))
        #expect(CPUSensors.isCPUKey("Te04", type: "flt "))
        #expect(!CPUSensors.isCPUKey("Tg0G", type: "flt "))
        #expect(!CPUSensors.isCPUKey("Tp00", type: "sp78"))
    }

    @Test func smcDecoding() {
        #expect(SMCDecode.float([0x00, 0x00, 0x0A, 0x42]) == 34.5)
        #expect(SMCDecode.float([0x00, 0x00, 0x50, 0x42]) == 52.0)
        #expect(SMCDecode.float([0x00, 0x00, 0x0A]) == nil)
        #expect(SMCDecode.unsigned([0x00, 0x00, 0x0B, 0x5A]) == 2906)
        #expect(SMCDecode.unsigned([0x01]) == 1)
        #expect(SMCDecode.string(fourCC: SMCDecode.fourCC("#KEY")) == "#KEY")
    }

    @Test func fanPercent() {
        #expect(FanSpeed.percent([(actual: 0, max: 6550)]) == 0)
        #expect(FanSpeed.percent([(actual: 3275, max: 6550)]) == 50)
        #expect(FanSpeed.percent([(actual: 7000, max: 6550)]) == 100)
        #expect(FanSpeed.percent([(actual: 3275, max: 6550), (actual: 0, max: 6550)]) == 25)
        #expect(FanSpeed.percent([(actual: 100, max: 0)]) == nil)
        #expect(FanSpeed.percent([]) == nil)
    }
}
