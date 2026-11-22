// Writes every HID temperature service and every readable SMC T* float key to CSV once a second until killed.
import Foundation
import IOKit

let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)!
func sym<T>(_ name: String, _ type: T.Type) -> T { unsafeBitCast(dlsym(iokit, name)!, to: type) }
typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double
let copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self)
let getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self)
let client = sym("IOHIDEventSystemClientCreate", CreateFn.self)(kCFAllocatorDefault)!.takeRetainedValue()
sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self)(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
let services = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self)(client)?.takeRetainedValue() as? [AnyObject] ?? []
let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self)
let hidNames = services.map { copyProperty($0, "Product" as CFString)?.takeRetainedValue() as? String ?? "?" }
func hidRead(_ service: AnyObject) -> Double? {
    guard let event = copyEvent(service, 15, 0, 0)?.takeRetainedValue() else { return nil }
    return getFloat(event, Int32(15 << 16))
}

struct SMCVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
struct SMCPLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0 }
struct SMCKeyInfoData { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
}
func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func fourStr(_ v: UInt32) -> String { String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) }, as: UTF8.self) }
var connection: io_connect_t = 0
let smcService = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard IOServiceOpen(smcService, mach_task_self_, 0, &connection) == KERN_SUCCESS else { fatalError("AppleSMC is unavailable") }
func call(_ input: SMCKeyData) -> SMCKeyData? {
    var input = input, output = SMCKeyData(), size = MemoryLayout<SMCKeyData>.stride
    let status = IOConnectCallStructMethod(connection, 2, &input, size, &output, &size)
    return status == KERN_SUCCESS && output.result == 0 ? output : nil
}
func smcRead(_ key: String) -> (type: String, bytes: [UInt8])? {
    var request = SMCKeyData()
    request.key = fourCC(key)
    request.data8 = 9
    guard let info = call(request)?.keyInfo else { return nil }
    request.keyInfo.dataSize = info.dataSize
    request.data8 = 5
    guard let reply = call(request) else { return nil }
    return (fourStr(info.dataType), withUnsafeBytes(of: reply.bytes) { Array($0.prefix(Int(min(info.dataSize, 32)))) })
}
func smcFloat(_ key: String) -> Double? {
    guard let value = smcRead(key), value.type == "flt ", value.bytes.count == 4 else { return nil }
    return Double(value.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
}
let keyCount = smcRead("#KEY").map { $0.bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } } ?? 0
let smcKeys = (0..<keyCount).compactMap { index -> String? in
    var request = SMCKeyData()
    request.data8 = 8
    request.data32 = index
    return call(request).map { fourStr($0.key) }
}.filter { $0.hasPrefix("T") && (smcFloat($0).map { (10...130).contains($0) } ?? false) }

let output = FileHandle(forWritingAtPath: CommandLine.arguments[1])!
func line(_ fields: [String]) { output.write((fields.joined(separator: ",") + "\n").data(using: .utf8)!) }
line(["t"] + hidNames.map { "hid:" + $0 } + smcKeys.map { "smc:" + $0 })
while true {
    let hid = services.map { hidRead($0).map { String(format: "%.2f", $0) } ?? "" }
    let smc = smcKeys.map { smcFloat($0).map { String(format: "%.2f", $0) } ?? "" }
    line(["\(Date().timeIntervalSince1970)"] + hid + smc)
    sleep(1)
}
