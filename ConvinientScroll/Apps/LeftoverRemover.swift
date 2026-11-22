import Foundation
import os

nonisolated enum PrivilegedError: Error, Equatable {
    case cancelled
    case failed(String)
}

nonisolated struct RemovalEnvironment: Sendable {
    var trash: @Sendable (URL) throws -> Void
    var bootoutUser: @Sendable (URL) -> Void
    var runPrivileged: @Sendable (String) throws(PrivilegedError) -> Void
    var exists: @Sendable (URL) -> Bool
    var userTrash: URL
    var now: @Sendable () -> Date

    static func live() -> RemovalEnvironment {
        RemovalEnvironment(
            trash: { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) },
            bootoutUser: { url in
                do {
                    let result = try runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())", url.path])
                    if result.status != 0 {
                        AppLog.apps.info("bootout \(url.path, privacy: .private) exited \(result.status)")
                    }
                } catch {
                    AppLog.apps.error("bootout \(url.path, privacy: .private) did not start: \(error.localizedDescription)")
                }
            },
            runPrivileged: { script throws(PrivilegedError) in
                let result: (status: Int32, stderr: String)
                do {
                    result = try runProcess("/usr/bin/osascript", ["-e", LeftoverRemover.appleScriptCommand(script)])
                } catch {
                    throw .failed(error.localizedDescription)
                }
                guard result.status != 0 else { return }
                throw result.stderr.contains("(-128)") ? .cancelled : .failed(result.stderr)
            },
            exists: { FileManager.default.fileExists(atPath: $0.path) },
            userTrash: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"),
            now: { Date() }
        )
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

nonisolated struct RemovalReport: Equatable, Sendable {
    var removed: [URL]
    var failed: [URL]
    var adminCancelled: Bool
    var bytes: Int64
}

nonisolated enum LeftoverRemover {
    static func remove(_ items: [LeftoverItem], environment: RemovalEnvironment) -> RemovalReport {
        var removed: [URL] = []
        var failed: [URL] = []
        var bytes: Int64 = 0

        let userItems = items.filter { $0.entry.domain == .user }
        let systemItems = items.filter { $0.entry.domain == .system }

        for item in userItems where item.kind == .service {
            environment.bootoutUser(item.id)
        }
        for item in userItems {
            do {
                try environment.trash(item.id)
                removed.append(item.id)
                bytes += item.size ?? 0
            } catch {
                AppLog.apps.error("trash failed \(item.id.path, privacy: .private): \(error.localizedDescription)")
                failed.append(item.id)
            }
        }

        guard !systemItems.isEmpty else {
            return RemovalReport(removed: removed, failed: failed, adminCancelled: false, bytes: bytes)
        }

        let stamp = stampString(environment.now())
        var assigned = Set<URL>()
        var destinations: [URL] = []
        for item in systemItems {
            var destination = trashDestination(
                for: item.id, in: environment.userTrash,
                exists: { assigned.contains($0) || environment.exists($0) }, stamp: stamp)
            if assigned.contains(destination) || environment.exists(destination) {
                let base = destination.deletingPathExtension()
                let ext = destination.pathExtension
                var counter = 2
                repeat {
                    let name = "\(base.lastPathComponent) \(counter)"
                    destination = environment.userTrash.appending(path: ext.isEmpty ? name : "\(name).\(ext)")
                    counter += 1
                } while assigned.contains(destination) || environment.exists(destination)
            }
            assigned.insert(destination)
            destinations.append(destination)
        }

        let script = privilegedScript(
            items: systemItems.map(\.id),
            services: systemItems.filter { $0.kind == .service }.map(\.id),
            destinations: destinations)
        do {
            try environment.runPrivileged(script)
        } catch {
            switch error {
            case .cancelled:
                failed.append(contentsOf: systemItems.map(\.id))
                return RemovalReport(removed: removed, failed: failed, adminCancelled: true, bytes: bytes)
            case .failed(let message):
                AppLog.apps.error("privileged removal failed: \(message, privacy: .private)")
            }
        }

        for item in systemItems {
            if environment.exists(item.id) {
                failed.append(item.id)
            } else {
                removed.append(item.id)
                bytes += item.size ?? 0
            }
        }
        return RemovalReport(removed: removed, failed: failed, adminCancelled: false, bytes: bytes)
    }

    static func privilegedScript(items: [URL], services: [URL], destinations: [URL]) -> String {
        var lines = services.map { "/bin/launchctl bootout system \(shellQuoted($0.path)) 2>/dev/null" }
        for (source, destination) in zip(items, destinations) {
            lines.append("/bin/mv -n \(shellQuoted(source.path)) \(shellQuoted(destination.path))")
        }
        return lines.joined(separator: "\n")
    }

    static func trashDestination(for url: URL, in trash: URL, exists: (URL) -> Bool, stamp: String) -> URL {
        let plain = trash.appending(path: url.lastPathComponent)
        guard exists(plain) else { return plain }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        return trash.appending(path: ext.isEmpty ? "\(base) \(stamp)" : "\(base) \(stamp).\(ext)")
    }

    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptCommand(_ script: String) -> String {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private static func stampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH.mm.ss"
        return formatter.string(from: date)
    }
}
