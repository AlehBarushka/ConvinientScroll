import Foundation

/// Page counts from `host_statistics64(HOST_VM_INFO64)` that make up "Memory Used".
struct MemorySnapshot: Equatable {
    var internalPages: UInt64
    var purgeablePages: UInt64
    var wiredPages: UInt64
    var compressedPages: UInt64
    var pageSize: UInt64
}

/// RAM in use as Activity Monitor counts it: app memory, wired and compressed, without
/// file cache.
struct MemoryUsage: Equatable {
    let usedBytes: UInt64
    let totalBytes: UInt64

    init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    init(snapshot: MemorySnapshot, totalBytes: UInt64) {
        let appPages = snapshot.internalPages > snapshot.purgeablePages
            ? snapshot.internalPages - snapshot.purgeablePages
            : 0
        let pages = appPages + snapshot.wiredPages + snapshot.compressedPages
        self.init(usedBytes: pages * snapshot.pageSize, totalBytes: totalBytes)
    }

    var percent: Int {
        guard totalBytes > 0 else { return 0 }
        let value = (Double(usedBytes) / Double(totalBytes) * 100).rounded()
        return Int(min(max(value, 0), 100))
    }

    func detailText(pressure: MemoryPressure) -> String {
        "\(Self.gigabytes(usedBytes, decimals: 1)) of \(Self.gigabytes(totalBytes)) GB used · Pressure: \(pressure.title)"
    }

    private static func gigabytes(_ bytes: UInt64, decimals: Int? = nil) -> String {
        let value = Double(bytes) / Double(1 << 30)
        let places = decimals ?? (value == value.rounded() ? 0 : 1)
        return String(format: "%.\(places)f", value)
    }
}

enum MemoryPressure: Equatable {
    case normal, warning, critical

    /// Values of `kern.memorystatus_vm_pressure_level`.
    init(kernelLevel: Int) {
        switch kernelLevel {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

extension MemoryPressure {
    var tint: MenuBarTint {
        switch self {
        case .normal: .none
        case .warning: .warning
        case .critical: .critical
        }
    }
}
