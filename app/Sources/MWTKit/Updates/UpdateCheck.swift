import Foundation

public enum UpdateStatus: Equatable, Sendable {
    case upToDate
    case available(AppVersion)
    case failed(String)
}

public struct UpdateCheck: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let endpoint = URL(string: "https://api.github.com/repos/kromuch/multi-worktree/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/kromuch/multi-worktree/releases/latest")!
    public static let interval: Duration = .seconds(24 * 60 * 60)

    public let current: AppVersion
    private let fetch: Fetch

    public init(current: AppVersion, fetch: @escaping Fetch) {
        self.current = current
        self.fetch = fetch
    }

    public var request: URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MultiWorktree/\(current)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func run() async -> UpdateStatus {
        let result: (Data, URLResponse)
        do {
            result = try await fetch(request)
        } catch {
            return .failed(error.localizedDescription)
        }
        guard let http = result.1 as? HTTPURLResponse else { return .failed("not an HTTP response") }
        switch http.statusCode {
        case 200: return Self.status(from: result.0, current: current)
        case 404: return .upToDate
        default: return .failed("HTTP \(http.statusCode)")
        }
    }

    static func status(from data: Data, current: AppVersion) -> UpdateStatus {
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data) else {
            return .failed("unreadable release data")
        }
        guard let latest = AppVersion(release.tagName) else {
            return .failed("unrecognized release tag: \(release.tagName)")
        }
        return latest > current ? .available(latest) : .upToDate
    }

    private struct LatestRelease: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}

public enum UpdateNotice {
    public static func visible(status: UpdateStatus?, skipped: String?, dismissed: Bool) -> AppVersion? {
        guard !dismissed, case .available(let version)? = status, version.description != skipped else { return nil }
        return version
    }
}
