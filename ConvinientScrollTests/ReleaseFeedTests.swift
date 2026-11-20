import Foundation
import Testing
@testable import MacToolkit

@Suite("ReleaseFeed")
struct ReleaseFeedTests {
    private static let feedURL = URL(string: "https://example.test/releases/latest")!

    private func json(tag: String, assets: [String]) -> Data {
        let assetList = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://example.test/\#($0)"}"#
        }.joined(separator: ",")
        let body = #"{"tag_name":"\#(tag)","html_url":"https://github.com/x/y/releases/tag/\#(tag)","assets":[\#(assetList)]}"#
        return Data(body.utf8)
    }

    private func feed(_ data: Data, status: Int = 200) -> ReleaseFeed {
        ReleaseFeed(url: Self.feedURL) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    @Test func newerTagIsAvailable() async throws {
        let result = try await feed(json(tag: "2.4.0", assets: ["MacToolkit-2.4.0.dmg"]))
            .check(current: AppVersion("2.3.1")!)
        #expect(result == .available(AvailableUpdate(
            version: AppVersion("2.4.0")!,
            pageURL: URL(string: "https://github.com/x/y/releases/tag/2.4.0")!,
            diskImageURL: URL(string: "https://example.test/MacToolkit-2.4.0.dmg")!)))
    }

    @Test(arguments: ["2.3.1", "2.3.0"])
    func sameOrOlderTagIsUpToDate(tag: String) async throws {
        let result = try await feed(json(tag: tag, assets: []))
            .check(current: AppVersion("2.3.1")!)
        #expect(result == .upToDate(AppVersion("2.3.1")!))
    }

    @Test func picksFirstDiskImageCaseInsensitive() async throws {
        let result = try await feed(json(tag: "2.4.0", assets: ["notes.txt", "Mac.DMG", "b.dmg"]))
            .check(current: AppVersion("2.3.1")!)
        guard case .available(let update) = result else {
            Issue.record("expected available")
            return
        }
        #expect(update.diskImageURL == URL(string: "https://example.test/Mac.DMG")!)
    }

    @Test func missingDiskImageThrows() async {
        await #expect(throws: UpdateError.noDiskImage) {
            try await feed(json(tag: "2.4.0", assets: ["src.zip"])).check(current: AppVersion("2.3.1")!)
        }
    }

    @Test func badTagThrows() async {
        await #expect(throws: UpdateError.unreadableVersion(tag: "v2.4")) {
            try await feed(json(tag: "v2.4", assets: ["a.dmg"])).check(current: AppVersion("2.3.1")!)
        }
    }

    @Test(arguments: [403, 429])
    func rateLimitStatus(status: Int) async {
        await #expect(throws: UpdateError.rateLimited) {
            try await feed(Data(), status: status).check(current: AppVersion("2.3.1")!)
        }
    }

    @Test func otherStatusThrows() async {
        await #expect(throws: UpdateError.server(status: 500)) {
            try await feed(Data(), status: 500).check(current: AppVersion("2.3.1")!)
        }
    }

    @Test func transportErrorIsNetwork() async {
        let feed = ReleaseFeed(url: Self.feedURL) { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: UpdateError.network) {
            try await feed.check(current: AppVersion("2.3.1")!)
        }
    }

    @Test func nonHTTPResponseIsAccepted() async throws {
        let data = json(tag: "2.4.0", assets: ["a.dmg"])
        let feed = ReleaseFeed(url: Self.feedURL) { _ in
            (data, URLResponse(url: URL(string: "file:///x")!, mimeType: nil, expectedContentLength: -1, textEncodingName: nil))
        }
        let result = try await feed.check(current: AppVersion("2.3.1")!)
        guard case .available = result else {
            Issue.record("expected available")
            return
        }
    }

    @Test func requestAsksForGitHubJSON() async throws {
        let box = RequestBox()
        let data = json(tag: "2.3.0", assets: [])
        let feed = ReleaseFeed(url: Self.feedURL) { request in
            box.set(request)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await feed.check(current: AppVersion("2.3.1")!)
        #expect(box.request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    }
}

private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var request: URLRequest? { lock.withLock { stored } }
    func set(_ request: URLRequest) { lock.withLock { stored = request } }
}
