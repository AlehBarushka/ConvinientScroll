import Foundation
import Testing
@testable import MacToolkit

@Suite("CodeSignature") struct CodeSignatureTests {
    let me = SigningIdentity(teamID: "TEAM1", bundleID: "com.example.app")
    let expected = AppVersion("2.4.0")!

    @Test func acceptsSameTeamBundleAndVersion() throws {
        try CodeSignature.verify(candidate: me, candidateVersion: "2.4.0", current: me, expected: expected)
    }

    @Test func rejectsOtherTeam() {
        let other = SigningIdentity(teamID: "TEAM2", bundleID: me.bundleID)
        #expect(throws: UpdateError.wrongDeveloper) {
            try CodeSignature.verify(candidate: other, candidateVersion: "2.4.0", current: me, expected: expected)
        }
    }

    @Test func rejectsOtherBundleID() {
        let other = SigningIdentity(teamID: me.teamID, bundleID: "com.example.other")
        #expect(throws: UpdateError.wrongDeveloper) {
            try CodeSignature.verify(candidate: other, candidateVersion: "2.4.0", current: me, expected: expected)
        }
    }

    @Test func rejectsVersionMismatch() {
        #expect(throws: UpdateError.versionMismatch(found: "2.3.9", expected: "2.4.0")) {
            try CodeSignature.verify(candidate: me, candidateVersion: "2.3.9", current: me, expected: expected)
        }
    }

    @Test func rejectsMissingVersion() {
        #expect(throws: UpdateError.versionMismatch(found: "?", expected: "2.4.0")) {
            try CodeSignature.verify(candidate: me, candidateVersion: nil, current: me, expected: expected)
        }
    }

    @Test func unsignedBundleIsInvalid() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeSignatureTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("X.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleExecutable": "X",
            "CFBundleIdentifier": "com.example.unsigned",
            "CFBundlePackageType": "APPL",
        ]
        try (info as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("X"))

        #expect(throws: UpdateError.signatureInvalid) { try CodeSignature.identity(ofAppAt: app) }
    }

    @Test func testHostHasIdentity() throws {
        let id = try CodeSignature.identity(ofAppAt: Bundle.main.bundleURL)
        #expect(id.bundleID == Bundle.main.bundleIdentifier)
        #expect(!id.teamID.isEmpty)
    }

    @Test func pinningToAnotherTeamRejectsTestHost() throws {
        let host = try CodeSignature.identity(ofAppAt: Bundle.main.bundleURL)
        let other = SigningIdentity(teamID: host.teamID + "X", bundleID: host.bundleID)
        #expect(throws: UpdateError.signatureInvalid) {
            try CodeSignature.identity(ofAppAt: Bundle.main.bundleURL, pinnedTo: other)
        }
    }

    @Test func pinningToOwnIdentityAcceptsTestHost() throws {
        let host = try CodeSignature.identity(ofAppAt: Bundle.main.bundleURL)
        #expect(try CodeSignature.identity(ofAppAt: Bundle.main.bundleURL, pinnedTo: host) == host)
    }
}
