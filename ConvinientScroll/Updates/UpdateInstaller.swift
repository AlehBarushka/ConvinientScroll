import AppKit
import Foundation
import OSLog
import ServiceManagement

struct UpdateInstallerEnvironment {
    var download: (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> Void
    var extractApp: (URL, URL) async throws(UpdateError) -> URL
    var identity: (URL) throws(UpdateError) -> SigningIdentity
    var currentIdentity: () throws(UpdateError) -> SigningIdentity
    var versionOfApp: (URL) -> String?
    var isWritable: (String) -> Bool
    var fileExists: (String) -> Bool
    var makeStagingDirectory: () throws -> URL
    var launchHelper: ([String]) throws -> Void
    var terminate: () -> Void
    var loginItemEnabled: () -> Bool
    var unregisterLoginItem: () -> Void
    var pending: PendingUpdateStore
    var targetURL: URL
    var currentAppURL: URL

    static func live(launchAtLogin: LaunchAtLoginManager) -> Self {
        let appName = Bundle.main.bundleURL.lastPathComponent
        return Self(
            download: { url, destination, progress in
                let observer = DownloadProgressObserver(report: progress)
                defer { observer.invalidate() }
                let (location, response) = try await URLSession.shared.download(for: URLRequest(url: url), delegate: observer)
                try FileManager.default.moveItem(at: location, to: destination)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
            },
            extractApp: { dmg, staging throws(UpdateError) in
                try await DiskImage.extractApp(named: appName, from: dmg, into: staging)
            },
            identity: { app throws(UpdateError) in try CodeSignature.identity(ofAppAt: app) },
            currentIdentity: { () throws(UpdateError) in try CodeSignature.currentIdentity() },
            versionOfApp: { app in
                guard let data = try? Data(contentsOf: app.appending(path: "Contents/Info.plist")),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { return nil }
                return info["CFBundleShortVersionString"] as? String
            },
            isWritable: { FileManager.default.isWritableFile(atPath: $0) },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            makeStagingDirectory: {
                try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                            appropriateFor: URL(filePath: "/Applications"), create: true)
            },
            launchHelper: { arguments in
                guard let executable = arguments.first else { throw CocoaError(.executableNotLoadable) }
                let process = Process()
                process.executableURL = URL(filePath: executable)
                process.arguments = Array(arguments.dropFirst())
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
            },
            terminate: { NSApp.terminate(nil) },
            loginItemEnabled: {
                launchAtLogin.refresh()
                return launchAtLogin.isEnabled
            },
            unregisterLoginItem: {
                do {
                    try SMAppService.mainApp.unregister()
                } catch {
                    AppLog.updates.error("Couldn't remove the login item of the old copy: \(error.localizedDescription, privacy: .public)")
                }
                launchAtLogin.refresh()
            },
            pending: PendingUpdateStore(defaults: .standard),
            targetURL: URL(filePath: "/Applications", directoryHint: .isDirectory).appending(path: appName),
            currentAppURL: Bundle.main.bundleURL
        )
    }
}

final class UpdateInstaller {
    private let environment: UpdateInstallerEnvironment

    init(environment: UpdateInstallerEnvironment) {
        self.environment = environment
    }

    func install(_ update: AvailableUpdate, progress: @escaping @Sendable (Double) -> Void) async throws(UpdateError) {
        let target = environment.targetURL.path
        guard environment.isWritable("/Applications"),
              !environment.fileExists(target) || environment.isWritable(target)
        else {
            AppLog.updates.error("Update to \(update.version.description, privacy: .public) needs write access to /Applications")
            throw .applicationsNotWritable
        }

        var staging: URL?
        do {
            let directory = try makeStagingDirectory()
            staging = directory
            try await prepareAndHandOff(update, staging: directory, progress: progress)
        } catch {
            if let staging { try? FileManager.default.removeItem(at: staging) }
            environment.pending.clear()
            AppLog.updates.error("Update to \(update.version.description, privacy: .public) failed: \(error.message, privacy: .public)")
            throw error
        }
    }

    private func prepareAndHandOff(
        _ update: AvailableUpdate,
        staging: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws(UpdateError) {
        let dmg = staging.appending(path: "update.dmg")
        try await download(update.diskImageURL, to: dmg, progress: progress)

        let app = try await environment.extractApp(dmg, staging)
        try? FileManager.default.removeItem(at: dmg)

        try CodeSignature.verify(
            candidate: environment.identity(app),
            candidateVersion: environment.versionOfApp(app),
            current: environment.currentIdentity(),
            expected: update.version
        )

        let script = try copyHelperScript(into: staging)
        if Task.isCancelled { throw .cancelled }

        let loginItemEnabled = environment.loginItemEnabled()
        environment.pending.save(PendingUpdate(version: update.version.description,
                                               reregisterLoginItem: loginItemEnabled))
        do {
            try environment.launchHelper([
                "/bin/sh",
                script.path,
                "\(getpid())",
                app.path,
                environment.targetURL.path,
                environment.currentAppURL.path,
                PendingUpdateStore.failureFileURL.path,
            ])
        } catch {
            AppLog.updates.error("Couldn't start the install helper: \(Self.describe(error), privacy: .public)")
            throw .applicationsNotWritable
        }

        let runsFromTarget = environment.currentAppURL.standardizedFileURL.path
            == environment.targetURL.standardizedFileURL.path
        if loginItemEnabled, !runsFromTarget {
            environment.unregisterLoginItem()
        }
        environment.terminate()
    }

    private func makeStagingDirectory() throws(UpdateError) -> URL {
        do {
            return try environment.makeStagingDirectory()
        } catch {
            AppLog.updates.error("Couldn't create the staging directory: \(Self.describe(error), privacy: .public)")
            throw .applicationsNotWritable
        }
    }

    private func download(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws(UpdateError) {
        do {
            try await environment.download(url, destination, progress)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw .cancelled
            }
            AppLog.updates.error("Download failed: \(Self.describe(error), privacy: .public)")
            throw .network
        }
    }

    private func copyHelperScript(into staging: URL) throws(UpdateError) -> URL {
        let destination = staging.appending(path: "install-update.sh")
        guard let source = Bundle.main.url(forResource: "install-update", withExtension: "sh") else {
            AppLog.updates.error("The install helper script is missing from the app bundle")
            throw .applicationsNotWritable
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            AppLog.updates.error("Couldn't copy the install helper: \(Self.describe(error), privacy: .public)")
            throw .applicationsNotWritable
        }
        return destination
    }

    private static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code)"
    }
}

nonisolated private final class DownloadProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
        lock.withLock { self.observation = observation }
    }

    func invalidate() {
        lock.withLock {
            observation?.invalidate()
            observation = nil
        }
    }
}
