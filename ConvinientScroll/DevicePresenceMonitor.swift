import Foundation
import OSLog
import Combine
import IOKit.hid
import IOKit

@MainActor
final class DevicePresenceMonitor: ObservableObject {
    @Published private(set) var hasMouse: Bool = false
    @Published private(set) var hasTrackpad: Bool = false

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        recomputePresence()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recomputePresence()
            }
        }
    }

    private static let maxScanAttempts = 3

    private func recomputePresence() {
        var mouse = false
        var trackpad = false

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator)
        guard result == KERN_SUCCESS else {
            if hasMouse != false { hasMouse = false }
            if hasTrackpad != false { hasTrackpad = false }
            return
        }

        defer { IOObjectRelease(iterator) }

        // A device that appears or disappears mid-walk invalidates the iterator and
        // the walk ends early, so "not found" is only trustworthy for a valid one.
        // A positive result for both kinds is final either way.
        var attempt = 1
        while true {
            (mouse, trackpad) = scanDevices(iterator)
            if (mouse && trackpad) || IOIteratorIsValid(iterator) != 0 { break }
            guard attempt < Self.maxScanAttempts else {
                AppLog.devices.error("HID registry kept changing during \(attempt) scans; keeping the previous device state")
                return
            }
            attempt += 1
            IOIteratorReset(iterator)
        }

        if hasMouse != mouse { hasMouse = mouse }
        if hasTrackpad != trackpad { hasTrackpad = trackpad }
    }

    private func scanDevices(_ iterator: io_iterator_t) -> (mouse: Bool, trackpad: Bool) {
        var mouse = false
        var trackpad = false

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            let product = (IORegistryEntryCreateCFProperty(service, kIOHIDProductKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String)
            let productLower = product?.lowercased()

            guard
                let page = (IORegistryEntryCreateCFProperty(service, kIOHIDPrimaryUsagePageKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue,
                let usage = (IORegistryEntryCreateCFProperty(service, kIOHIDPrimaryUsageKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
            else {
                continue
            }

            // Heuristic: many Apple trackpads don't expose Digitizer/TouchPad usage.
            // Product strings often contain "trackpad", and those devices may also report mouse-like usages.
            if let productLower, productLower.contains("trackpad") {
                trackpad = true
                if mouse, trackpad { break }
                continue
            }

            if page == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_Mouse {
                mouse = true
            } else if page == kHIDPage_Digitizer, usage == kHIDUsage_Dig_TouchPad {
                trackpad = true
            } else if let productLower, productLower.contains("mouse") {
                mouse = true
            }

            if mouse, trackpad { break }
        }

        return (mouse, trackpad)
    }
}

