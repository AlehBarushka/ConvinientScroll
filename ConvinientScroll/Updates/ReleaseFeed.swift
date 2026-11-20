import Foundation

nonisolated struct AvailableUpdate: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
    let diskImageURL: URL
}

nonisolated enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(AppVersion)
    case available(AvailableUpdate)
}

nonisolated struct ReleaseFeed {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let defaultURL = URL(string: "https://api.github.com/repos/AlehBarushka/ConvinientScroll/releases/latest")!

    static var configuredURL: URL {
        #if DEBUG
        if let string = UserDefaults.standard.string(forKey: "UpdateFeedURL"), let url = URL(string: string) {
            return url
        }
        #endif
        return defaultURL
    }

    let url: URL
    let fetch: Fetch

    init(url: URL, fetch: @escaping Fetch) {
        self.url = url
        self.fetch = fetch
    }

    static func live() -> ReleaseFeed {
        ReleaseFeed(url: configuredURL) { request in
            try await URLSession.shared.data(for: request)
        }
    }

    func check(current: AppVersion) async throws(UpdateError) -> UpdateCheckResult {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            throw .network
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 403, 429: throw .rateLimited
            default: throw .server(status: http.statusCode)
            }
        }

        guard let release = try? JSONDecoder().decode(Release.self, from: data) else {
            throw .network
        }
        guard let version = AppVersion(release.tagName) else {
            throw .unreadableVersion(tag: release.tagName)
        }
        guard version > current else { return .upToDate(current) }
        guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw .noDiskImage
        }
        return .available(AvailableUpdate(version: version, pageURL: release.htmlURL, diskImageURL: asset.downloadURL))
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }
}
