import Darwin
import Foundation
import OSLog

enum SystemMemory {
    /// Each `mach_host_self()` call adds a reference to the host port, so it is taken once.
    private static let host = mach_host_self()

    static let totalBytes = ProcessInfo.processInfo.physicalMemory

    static func usage() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            AppLog.memory.error("host_statistics64 failed: \(result, privacy: .public)")
            return nil
        }
        // The kernel page size, not `vm_page_size`: they differ under Rosetta.
        let snapshot = MemorySnapshot(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(vm_kernel_page_size)
        )
        return MemoryUsage(snapshot: snapshot, totalBytes: totalBytes)
    }

    /// The pressure source reports only transitions, so the level at start comes from here.
    static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryPressure(kernelLevel: Int(level))
    }
}
