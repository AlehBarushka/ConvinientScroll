import Foundation

nonisolated enum DiskImage {
    static let processTimeout: TimeInterval = 120

    struct Outcome {
        var status: Int32
        var output: Data
        var timedOut = false
        var cancelled = false
    }

    static func extractApp(named appName: String, from dmg: URL, into directory: URL) async throws(UpdateError) -> URL {
        let attach = await run("/usr/bin/hdiutil",
                               ["attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify", "-plist", dmg.path])
        if attach.cancelled { throw .cancelled }

        let entities = systemEntities(in: attach.output)
        let mountPoint = entities.lazy.compactMap { $0["mount-point"] as? String }.first
        let detachTarget = mountPoint ?? entities.lazy.compactMap { $0["dev-entry"] as? String }.first

        let result: Result<URL, UpdateError>
        if attach.status == 0, !attach.timedOut, let mountPoint {
            result = await copyApp(named: appName, fromVolume: mountPoint, into: directory)
        } else {
            result = .failure(.diskImageUnreadable)
        }

        if attach.status == 0, let detachTarget {
            await Task.detached { await detach(detachTarget) }.value
        }
        return try result.get()
    }

    private static func copyApp(named appName: String, fromVolume mountPoint: String, into directory: URL) async -> Result<URL, UpdateError> {
        let source = URL(filePath: mountPoint).appending(path: appName)
        guard FileManager.default.fileExists(atPath: source.path) else { return .failure(.appNotInImage) }

        let destination = directory.appending(path: appName)
        let copy = await run("/usr/bin/ditto", [source.path, destination.path])
        if copy.cancelled { return .failure(.cancelled) }
        guard copy.status == 0, !copy.timedOut else { return .failure(.diskImageUnreadable) }
        return .success(destination)
    }

    private static func systemEntities(in plist: Data) -> [[String: Any]] {
        let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return root?["system-entities"] as? [[String: Any]] ?? []
    }

    private static func detach(_ target: String) async {
        _ = await run("/usr/bin/hdiutil", ["detach", target, "-force"])
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = processTimeout) async -> Outcome {
        let runner = Runner(executable: executable, arguments: arguments, timeout: timeout)
        return await withTaskCancellationHandler {
            await runner.start()
        } onCancel: {
            runner.stop(timedOut: false)
        }
    }

    private final class Runner: @unchecked Sendable {
        private let lock = NSLock()
        private let process = Process()
        private let pipe = Pipe()
        private let timeout: TimeInterval
        private var stopped = false
        private var timedOut = false
        private var finished = false

        init(executable: String, arguments: [String], timeout: TimeInterval) {
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            self.timeout = timeout
        }

        func start() async -> Outcome {
            await withCheckedContinuation { continuation in
                lock.lock()
                if stopped {
                    lock.unlock()
                    continuation.resume(returning: Outcome(status: -1, output: Data(), cancelled: true))
                    return
                }
                process.terminationHandler = { [self] finished in
                    let output = pipe.fileHandleForReading.readDataToEndOfFile()
                    lock.lock()
                    self.finished = true
                    let outcome = Outcome(status: finished.terminationStatus, output: output,
                                          timedOut: timedOut, cancelled: stopped && !timedOut)
                    lock.unlock()
                    continuation.resume(returning: outcome)
                }
                do {
                    try process.run()
                    lock.unlock()
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                        stop(timedOut: true)
                    }
                } catch {
                    lock.unlock()
                    process.terminationHandler = nil
                    continuation.resume(returning: Outcome(status: -1, output: Data()))
                }
            }
        }

        func stop(timedOut byTimeout: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished, !stopped else { return }
            stopped = true
            timedOut = byTimeout
            if process.isRunning { process.terminate() }
        }
    }
}
