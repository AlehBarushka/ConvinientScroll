import Foundation
import Testing
@testable import MacToolkit

@MainActor
@Suite("MemoryUsage")
struct MemoryUsageTests {
    private let gib: UInt64 = 1 << 30
    private let page: UInt64 = 16_384

    @Test func usedMemoryCountsAppWiredAndCompressedButNotCache() {
        let snapshot = MemorySnapshot(
            internalPages: 1_000_000,
            purgeablePages: 50_000,
            wiredPages: 300_000,
            compressedPages: 100_000,
            pageSize: page
        )
        let usage = MemoryUsage(snapshot: snapshot, totalBytes: 32 * gib)
        #expect(usage.usedBytes == 1_350_000 * page)
        #expect(usage.percent == 64)
    }

    @Test func percentRoundsToNearestWhole() {
        #expect(MemoryUsage(usedBytes: 566 * gib / 1000 * 32, totalBytes: 32 * gib).percent == 57)
        #expect(MemoryUsage(usedBytes: 564 * gib / 1000 * 32, totalBytes: 32 * gib).percent == 56)
    }

    @Test func purgeableAboveInternalDoesNotWrapAround() {
        let snapshot = MemorySnapshot(
            internalPages: 10,
            purgeablePages: 20,
            wiredPages: 5,
            compressedPages: 0,
            pageSize: page
        )
        #expect(MemoryUsage(snapshot: snapshot, totalBytes: gib).usedBytes == 5 * page)
    }

    @Test func percentStaysWithinZeroAndHundred() {
        #expect(MemoryUsage(usedBytes: 40 * gib, totalBytes: 32 * gib).percent == 100)
        #expect(MemoryUsage(usedBytes: gib, totalBytes: 0).percent == 0)
    }

    @Test func detailLineShowsGigabytesAndPressure() {
        let usage = MemoryUsage(usedBytes: 18_120 * gib / 1000, totalBytes: 32 * gib)
        #expect(usage.detailText(pressure: .normal) == "18.1 of 32 GB used · Pressure: Normal")
        #expect(usage.detailText(pressure: .warning) == "18.1 of 32 GB used · Pressure: Warning")
        #expect(usage.detailText(pressure: .critical) == "18.1 of 32 GB used · Pressure: Critical")
    }

    @Test func detailLineKeepsFractionalTotal() {
        let usage = MemoryUsage(usedBytes: 6 * gib, totalBytes: 12 * gib + gib / 2)
        #expect(usage.detailText(pressure: .normal) == "6.0 of 12.5 GB used · Pressure: Normal")
    }

    @Test func systemReadingIsPlausible() throws {
        let usage = try #require(SystemMemory.usage())
        #expect(usage.totalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(usage.usedBytes > 0)
        #expect(usage.usedBytes <= usage.totalBytes)
    }

    @Test func kernelPressureLevelsMapToStates() {
        #expect(MemoryPressure(kernelLevel: 1) == .normal)
        #expect(MemoryPressure(kernelLevel: 2) == .warning)
        #expect(MemoryPressure(kernelLevel: 4) == .critical)
        #expect(MemoryPressure(kernelLevel: 0) == .normal)
    }
}
