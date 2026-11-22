import CoreServices
import Foundation
import OSLog

protocol FolderWatching: AnyObject {
    func start(_ folders: [URL], onChange: @escaping () -> Void)
    func stop()
}

final class ApplicationsWatcher: FolderWatching {
    static let latency: CFTimeInterval = 2

    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?

    func start(_ folders: [URL], onChange: @escaping () -> Void) {
        stop()
        let paths = folders.map(\.path).filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ApplicationsWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange?() }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer))
        else {
            AppLog.apps.error("Cannot create FSEvents stream for Applications folders")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            AppLog.apps.error("Cannot start FSEvents stream for Applications folders")
            return
        }
        self.stream = stream
        self.onChange = onChange
    }

    func stop() {
        onChange = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    isolated deinit {
        stop()
    }
}
