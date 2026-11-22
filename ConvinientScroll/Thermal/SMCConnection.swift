import Foundation
import IOKit

nonisolated struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

nonisolated struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

nonisolated struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var pad: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

nonisolated struct SMCKeyData {
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

nonisolated final class SMCConnection {
    private enum Command: UInt8 {
        case read = 5
        case keyByIndex = 8
        case keyInfo = 9
    }

    private let connection: io_connect_t
    private var keyInfo: [UInt32: SMCKeyInfoData] = [:]

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var request = SMCKeyData()
        request.key = SMCDecode.fourCC(key)
        guard let info = info(for: request.key) else { return nil }
        request.keyInfo.dataSize = info.dataSize
        request.data8 = Command.read.rawValue
        guard let reply = call(request) else { return nil }
        let size = min(Int(info.dataSize), 32)
        let bytes = withUnsafeBytes(of: reply.bytes) { Array($0.prefix(size)) }
        return (SMCDecode.string(fourCC: info.dataType), bytes)
    }

    func keys() -> [String] {
        guard let count = read("#KEY").flatMap({ SMCDecode.unsigned($0.bytes) }) else { return [] }
        return (0..<count).compactMap { index in
            var request = SMCKeyData()
            request.data8 = Command.keyByIndex.rawValue
            request.data32 = index
            return call(request).map { SMCDecode.string(fourCC: $0.key) }
        }
    }

    private func info(for key: UInt32) -> SMCKeyInfoData? {
        if let cached = keyInfo[key] { return cached }
        var request = SMCKeyData()
        request.key = key
        request.data8 = Command.keyInfo.rawValue
        guard let info = call(request)?.keyInfo else { return nil }
        keyInfo[key] = info
        return info
    }

    private func call(_ request: SMCKeyData) -> SMCKeyData? {
        var input = request
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let status = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCKeyData>.stride, &output, &outputSize)
        guard status == KERN_SUCCESS, output.result == 0 else { return nil }
        return output
    }
}

nonisolated final class SMCTemperatureSource: CPUTemperatureSource {
    let sensorNames: [String]
    private let smc: SMCConnection
    private var hottest: HottestSensors

    init?(smc: SMCConnection) {
        let keys = smc.keys().filter { key in
            guard key.hasPrefix("Tp") || key.hasPrefix("Te"),
                  let value = smc.read(key),
                  CPUSensors.isCPUKey(key, type: value.type),
                  let celsius = SMCDecode.float(value.bytes) else { return false }
            return CPUSensors.plausibleRange.contains(celsius)
        }
        guard !keys.isEmpty else { return nil }
        self.smc = smc
        self.sensorNames = keys
        self.hottest = HottestSensors(count: keys.count)
    }

    func read() -> Double? {
        hottest.read { index in smc.read(sensorNames[index]).flatMap { SMCDecode.float($0.bytes) } }
    }
}
