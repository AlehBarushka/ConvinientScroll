import Foundation
import OSLog
import Combine
import IOKit.hid
import IOKit
import AppKit

@MainActor
final class DevicePresenceMonitor: ObservableObject {
    @Published private(set) var hasMouse: Bool = false
    @Published private(set) var hasTrackpad: Bool = false

    /// IOKit reports HID devices appearing and disappearing, so the registry is walked
    /// only when something changed instead of on a timer.
    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var recomputeScheduled = false
    private var wakeObserver: NSObjectProtocol?

    /// One device usually brings several HID interfaces; their events are coalesced.
    private static let coalescingDelay: DispatchTimeInterval = .milliseconds(150)

    func start() {
        guard notificationPort == nil else { return }
        recomputePresence()

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            AppLog.devices.error("Cannot create an IOKit notification port; device changes will not be noticed")
            return
        }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .commonModes)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for (type, iterator) in [(kIOFirstMatchNotification, \DevicePresenceMonitor.matchedIterator),
                                 (kIOTerminatedNotification, \DevicePresenceMonitor.terminatedIterator)] {
            var it: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, IOServiceMatching(kIOHIDDeviceKey), hidDevicesChanged, context, &it)
            if result == KERN_SUCCESS {
                // The iterator must be drained to arm the notification.
                drainIterator(it)
                self[keyPath: iterator] = it
            } else {
                AppLog.devices.error("IOServiceAddMatchingNotification failed: \(result)")
            }
        }

        // Bluetooth devices may reconnect while the Mac sleeps.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRecompute() }
        }
    }

    fileprivate func scheduleRecompute() {
        guard !recomputeScheduled else { return }
        recomputeScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalescingDelay) { [weak self] in
            guard let self else { return }
            self.recomputeScheduled = false
            self.recomputePresence()
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


private nonisolated func drainIterator(_ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
    }
}

/// Called on the main run loop, where the notification port's source was added.
private nonisolated let hidDevicesChanged: IOServiceMatchingCallback = { refcon, iterator in
    drainIterator(iterator)
    guard let refcon else { return }
    let monitor = Unmanaged<DevicePresenceMonitor>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.scheduleRecompute() }
}
