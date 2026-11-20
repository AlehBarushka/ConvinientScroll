import Foundation

nonisolated enum DiskImage {
    static func extractApp(named appName: String, from dmg: URL, into directory: URL) async throws(UpdateError) -> URL {
        let attach = await run("/usr/bin/hdiutil",
                               ["attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify", "-plist", dmg.path])
        guard attach.status == 0, let mountPoint = mountPoint(in: attach.output) else {
            throw .diskImageUnreadable
        }
        defer { detach(mountPoint) }

        let source = URL(filePath: mountPoint).appending(path: appName)
        guard FileManager.default.fileExists(atPath: source.path) else { throw .appNotInImage }

        let destination = directory.appending(path: appName)
        let copy = await run("/usr/bin/ditto", [source.path, destination.path])
        guard copy.status == 0 else { throw .diskImageUnreadable }
        return destination
    }

    private static func mountPoint(in plist: Data) -> String? {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]] else { return nil }
        return entities.lazy.compactMap { $0["mount-point"] as? String }.first
    }

    private static func detach(_ mountPoint: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }

    private static func run(_ executable: String, _ arguments: [String]) async -> (status: Int32, output: Data) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus, output))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: (-1, Data()))
            }
        }
    }
}
