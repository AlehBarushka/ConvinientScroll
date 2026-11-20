import Foundation
import Testing
@testable import MacToolkit

@Suite("DiskImage") struct DiskImageTests {
    private func hdiutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func withWorkspace(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DiskImageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if let info = try? hdiutil(["info"]), info.contains(root.lastPathComponent) {
                _ = try? hdiutil(["detach", "/Volumes/Test", "-force"])
            }
            try? FileManager.default.removeItem(at: root)
        }
        try await body(root)
    }

    private func makeImage(in root: URL, appNamed appName: String) throws -> URL {
        let source = root.appending(path: "src", directoryHint: .isDirectory)
        let contents = source.appending(path: "\(appName)/Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: contents.appending(path: "Info.plist"))
        let image = root.appending(path: "Test.dmg")
        _ = try hdiutil(["create", "-quiet", "-fs", "APFS", "-format", "UDZO",
                         "-srcfolder", source.path, "-volname", "Test", image.path])
        return image
    }

    private func makeOutput(in root: URL) throws -> URL {
        let output = root.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return output
    }

    private func isAttached(_ image: URL) throws -> Bool {
        try hdiutil(["info"]).contains(image.path)
    }

    @Test func extractsNamedApp() async throws {
        try await withWorkspace { root in
            let image = try makeImage(in: root, appNamed: "MacToolkit.app")
            let output = try makeOutput(in: root)

            let app = try await DiskImage.extractApp(named: "MacToolkit.app", from: image, into: output)

            #expect(app == output.appending(path: "MacToolkit.app"))
            #expect(FileManager.default.fileExists(atPath: app.appending(path: "Contents/Info.plist").path))
            #expect(try !isAttached(image))
        }
    }

    @Test func missingAppThrows() async throws {
        try await withWorkspace { root in
            let image = try makeImage(in: root, appNamed: "Other.app")
            let output = try makeOutput(in: root)

            await #expect(throws: UpdateError.appNotInImage) {
                try await DiskImage.extractApp(named: "MacToolkit.app", from: image, into: output)
            }
            #expect(try !isAttached(image))
        }
    }

    @Test func notAnImageThrows() async throws {
        try await withWorkspace { root in
            let fake = root.appending(path: "Fake.dmg")
            try Data("not an image".utf8).write(to: fake)
            let output = try makeOutput(in: root)

            await #expect(throws: UpdateError.diskImageUnreadable) {
                try await DiskImage.extractApp(named: "MacToolkit.app", from: fake, into: output)
            }
        }
    }
}
