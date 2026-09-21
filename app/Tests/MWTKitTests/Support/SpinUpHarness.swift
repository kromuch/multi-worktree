import Foundation
import Testing
@testable import MWTKit

final class OpenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func record(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    var opened: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

struct SpinUpHarness {
    let root: URL
    let home: URL
    let main: GitFixture
    let sibling: GitFixture
    let store: ConfigStore
    let opener = OpenRecorder()
    let feature = try! FeatureName.parse("NODE-1")

    init() throws {
        root = try TempDir.make()
        home = root.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        main = try GitFixture(name: "ari", root: root)
        sibling = try GitFixture(name: "other", root: root)
        store = ConfigStore(paths: MWTPaths(home: home))
    }

    var git: ShellGitClient { main.git }

    var group: RepoGroup {
        RepoGroup(name: "set", repos: [RepoEntry(path: main.repo.path, isMain: true), RepoEntry(path: sibling.repo.path, isMain: false)])
    }

    var environment: SpinUpEnvironment {
        let recorder = opener
        return SpinUpEnvironment(
            git: git,
            store: store,
            claudeJSON: home.appending(path: ".claude.json"),
            scratchDir: root.appending(path: "scratch"),
            open: { recorder.record($0) },
            now: { Date(timeIntervalSince1970: 1_758_400_000) })
    }

    func spinUp(group: RepoGroup? = nil, openClaude: Bool = true, choices: [String: BaseChoice] = [:]) throws -> (manifest: FeatureManifest, report: RunReport) {
        let g = group ?? self.group
        let preflights = Preflight(git: git).runAll(group: g, feature: feature)
        return try SpinUp(env: environment).run(SpinUpRequest(group: g, feature: feature, baseChoices: choices, openClaude: openClaude), preflights: preflights)
    }

    var mainWorktree: URL { store.paths.worktreeURL(segment: feature.segment, basename: "ari") }
    var siblingWorktree: URL { store.paths.worktreeURL(segment: feature.segment, basename: "other") }

    func settings() throws -> [String: Any] {
        let data = try Data(contentsOf: mainWorktree.appending(path: ".claude/settings.local.json"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["permissions"] as? [String: Any])
    }
}
