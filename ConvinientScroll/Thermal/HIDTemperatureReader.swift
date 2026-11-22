import Foundation

nonisolated protocol CPUTemperatureSource: AnyObject {
    var sensorNames: [String] { get }
    func read() -> Double?
}

nonisolated final class HIDTemperatureReader: CPUTemperatureSource {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static let temperatureEvent: Int64 = 15
    private static let temperatureField = Int32(15 << 16)

    let sensorNames: [String]
    private let client: AnyObject
    private let services: [AnyObject]
    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn

    init?() {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = Self.symbol(handle, "IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = Self.symbol(handle, "IOHIDEventSystemClientSetMatching", SetMatchingFn.self),
              let copyServices = Self.symbol(handle, "IOHIDEventSystemClientCopyServices", CopyServicesFn.self),
              let copyProperty = Self.symbol(handle, "IOHIDServiceClientCopyProperty", CopyPropertyFn.self),
              let copyEvent = Self.symbol(handle, "IOHIDServiceClientCopyEvent", CopyEventFn.self),
              let getFloat = Self.symbol(handle, "IOHIDEventGetFloatValue", GetFloatFn.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }

        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let all = copyServices(client)?.takeRetainedValue() as? [AnyObject] ?? []
        let dies = all.compactMap { service -> (String, AnyObject)? in
            guard let name = copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  CPUSensors.isCPUDie(name: name) else { return nil }
            return (name, service)
        }
        guard !dies.isEmpty else { return nil }

        self.client = client
        self.services = dies.map(\.1)
        self.sensorNames = dies.map(\.0)
        self.copyEvent = copyEvent
        self.getFloat = getFloat
    }

    func read() -> Double? {
        let readings = zip(sensorNames, services).compactMap { name, service -> SensorReading? in
            guard let event = copyEvent(service, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
            return SensorReading(name: name, celsius: getFloat(event, Self.temperatureField))
        }
        return CPUSensors.hottest(readings)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, _ type: T.Type) -> T? {
        dlsym(handle, name).map { unsafeBitCast($0, to: type) }
    }
}
