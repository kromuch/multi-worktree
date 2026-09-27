import Foundation
import Testing
@testable import MWTKit

actor RequestLog {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}

@Suite struct UpdateCheckTests {
    static let current = AppVersion(major: 0, minor: 1, patch: 1)

    static func respond(_ status: Int, _ body: String, log: RequestLog? = nil) -> UpdateCheck.Fetch {
        { request in
            await log?.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    static func check(_ status: Int, _ body: String) async -> UpdateStatus {
        await UpdateCheck(current: current, fetch: respond(status, body)).run()
    }

    @Test func newerReleaseIsAvailable() async {
        let status = await Self.check(200, #"{"tag_name":"v0.2.0","html_url":"https://github.com/kromuch/multi-worktree/releases/tag/v0.2.0"}"#)
        #expect(status == .available(AppVersion(major: 0, minor: 2, patch: 0)))
    }

    @Test func equalOrOlderReleaseIsUpToDate() async {
        #expect(await Self.check(200, #"{"tag_name":"v0.1.1"}"#) == .upToDate)
        #expect(await Self.check(200, #"{"tag_name":"0.1.0"}"#) == .upToDate)
    }

    @Test func noPublishedReleaseIsUpToDate() async {
        #expect(await Self.check(404, #"{"message":"Not Found"}"#) == .upToDate)
    }

    @Test func otherStatusesFail() async {
        #expect(await Self.check(403, #"{"message":"API rate limit exceeded"}"#) == .failed("HTTP 403"))
        #expect(await Self.check(500, "") == .failed("HTTP 500"))
    }

    @Test func unreadableBodiesFail() async {
        #expect(await Self.check(200, "<html></html>") == .failed("unreadable release data"))
        #expect(await Self.check(200, #"{"name":"no tag"}"#) == .failed("unreadable release data"))
        #expect(await Self.check(200, #"{"tag_name":"nightly"}"#) == .failed("unrecognized release tag: nightly"))
    }

    @Test func thrownErrorsFail() async {
        let check = UpdateCheck(current: Self.current) { _ in throw URLError(.notConnectedToInternet) }
        let status = await check.run()
        guard case .failed(let reason) = status else {
            Issue.record("expected a failure, got \(status)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func requestTargetsTheLatestReleaseWithRequiredHeaders() {
        let request = UpdateCheck(current: Self.current, fetch: Self.respond(404, "")).request
        #expect(request.url == UpdateCheck.endpoint)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/kromuch/multi-worktree/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MultiWorktree/0.1.1")
        #expect(request.timeoutInterval == 15)
    }

    @Test func runSendsThatRequest() async {
        let log = RequestLog()
        _ = await UpdateCheck(current: Self.current, fetch: Self.respond(404, "", log: log)).run()
        let sent = await log.requests
        #expect(sent.count == 1)
        #expect(sent.first?.url == UpdateCheck.endpoint)
        #expect(sent.first?.value(forHTTPHeaderField: "User-Agent") == "MultiWorktree/0.1.1")
    }

    @Test func noticeHidesSkippedAndDismissedVersions() {
        let v020 = AppVersion(major: 0, minor: 2, patch: 0)
        let v030 = AppVersion(major: 0, minor: 3, patch: 0)
        #expect(UpdateNotice.visible(status: .available(v020), skipped: nil, dismissed: false) == v020)
        #expect(UpdateNotice.visible(status: .available(v020), skipped: "0.2.0", dismissed: false) == nil)
        #expect(UpdateNotice.visible(status: .available(v030), skipped: "0.2.0", dismissed: false) == v030)
        #expect(UpdateNotice.visible(status: .available(v020), skipped: nil, dismissed: true) == nil)
        #expect(UpdateNotice.visible(status: .upToDate, skipped: nil, dismissed: false) == nil)
        #expect(UpdateNotice.visible(status: .failed("HTTP 403"), skipped: nil, dismissed: false) == nil)
        #expect(UpdateNotice.visible(status: nil, skipped: nil, dismissed: false) == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MWT_LIVE_NETWORK"] == "1"))
    func liveRequestSucceeds() async throws {
        let current = try #require(AppVersion(KitInfo.version))
        let session = URLSession(configuration: .ephemeral)
        let status = await UpdateCheck(current: current, fetch: { try await session.data(for: $0) }).run()
        if case .failed(let reason) = status {
            Issue.record("live update check failed: \(reason)")
        }
    }
}
