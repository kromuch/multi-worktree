import Foundation
import Observation
import MWTKit

enum OpenError: Error {
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    enum Screen: Equatable {
        case home
        case editGroup(RepoGroup?)
        case spinUp(RepoGroup)
        case tearDown(FeatureManifest)
        case report
    }

    enum ReportKind {
        case spinUp
        case tearDown
    }

    var screen: Screen = .home
    var groups: [RepoGroup] = []
    var features: [FeatureManifest] = []
    var lastReport: RunReport?
    var lastReportKind: ReportKind = .spinUp
    var lastMainWorktree: URL?
    var lastError: String?
    var isBusy = false

    let store: ConfigStore
    let git: ShellGitClient
    private let claudeJSON: URL
    private let scratchDir: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        store = ConfigStore(paths: MWTPaths(home: home))
        git = ShellGitClient(gitPath: ToolEnvironment.resolveGit() ?? "/usr/bin/git", runner: ProcessRunner())
        claudeJSON = home.appending(path: ".claude.json")
        scratchDir = FileManager.default.temporaryDirectory.appending(path: "mwt-scratch")
        reload()
    }

    func reload() {
        do {
            groups = try store.loadGroups().groups
            features = try store.listManifests()
        } catch {
            lastError = String(describing: error)
        }
    }

    func saveGroup(_ group: RepoGroup, replacing oldName: String?) {
        do {
            var file = try store.loadGroups()
            file.groups.removeAll { $0.name == oldName || $0.name == group.name }
            file.groups.append(group)
            file.groups.sort { $0.name < $1.name }
            try store.saveGroups(file)
            lastError = nil
            reload()
            screen = .home
        } catch {
            lastError = String(describing: error)
        }
    }

    func deleteGroup(named name: String) {
        do {
            var file = try store.loadGroups()
            file.groups.removeAll { $0.name == name }
            try store.saveGroups(file)
            reload()
            screen = .home
        } catch {
            lastError = String(describing: error)
        }
    }

    func normalizedRepoPath(_ path: String) throws -> String {
        try git.topLevel(of: URL(fileURLWithPath: path)).path
    }

    func preflight(group: RepoGroup, feature: FeatureName) async -> [String: Result<RepoPreflight, PreflightError>] {
        let git = self.git
        return await Task.detached { Preflight(git: git).runAll(group: group, feature: feature) }.value
    }

    func spinUp(group: RepoGroup, feature: FeatureName, choices: [String: BaseChoice],
                preflights: [String: Result<RepoPreflight, PreflightError>], openClaude: Bool) async {
        isBusy = true
        defer { isBusy = false }
        let env = SpinUpEnvironment(git: git, store: store, claudeJSON: claudeJSON, scratchDir: scratchDir,
                                    open: { try AppModel.open($0) }, now: { Date() })
        let request = SpinUpRequest(group: group, feature: feature, baseChoices: choices, openClaude: openClaude)
        do {
            let result = try await Task.detached { try SpinUp(env: env).run(request, preflights: preflights) }.value
            lastReport = result.report
            lastMainWorktree = URL(fileURLWithPath: result.manifest.mainWorktree)
            lastError = nil
        } catch {
            lastReport = nil
            lastError = String(describing: error)
        }
        lastReportKind = .spinUp
        reload()
        screen = .report
    }

    func tearDown(segment: String, confirmed: Set<String>) async -> (manifest: FeatureManifest?, report: RunReport)? {
        isBusy = true
        defer { isBusy = false }
        let git = self.git
        let store = self.store
        let request = TearDownRequest(segment: segment, discardConfirmedRepoPaths: confirmed)
        do {
            let result = try await Task.detached { try TearDown(git: git, store: store).run(request) }.value
            lastReport = result.report
            lastReportKind = .tearDown
            lastError = nil
            reload()
            return result
        } catch {
            lastReport = nil
            lastError = String(describing: error)
            reload()
            return nil
        }
    }

    func openClaude(at folder: URL) {
        do {
            try Self.open(DeepLink.newSession(folder: folder))
        } catch {
            lastError = String(describing: error)
        }
    }

    nonisolated static func open(_ url: URL) throws {
        let result = try ProcessRunner().run("/usr/bin/open", [url.absoluteString], cwd: nil, extraEnvironment: [:])
        guard result.succeeded else { throw OpenError.failed(result.stderr) }
    }
}
