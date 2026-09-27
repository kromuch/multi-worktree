import Foundation
import AppKit
import Observation
import MWTKit

struct OpenError: Error, CustomStringConvertible {
    let url: URL
    let message: String

    var description: String {
        "Could not open \(url.absoluteString): \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
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

    enum DependencyState: Equatable {
        case checking
        case checked(DependencyReport)
    }

    static let claudeDownloadURL = URL(string: "https://claude.com/download")!
    static let claudeMissingHelp = "Claude desktop app not found"
    static let checkForUpdatesKey = "checkForUpdates"
    static let skippedUpdateKey = "skippedUpdateVersion"

    var screen: Screen = .home
    var groups: [RepoGroup] = []
    var features: [FeatureManifest] = []
    var lastReport: RunReport?
    var lastReportKind: ReportKind = .spinUp
    var lastMainWorktree: URL?
    var lastError: String?
    var isBusy = false
    var dependencies: DependencyState = .checking
    var update: UpdateStatus?
    var updateDismissed = false
    var skippedUpdateVersion: String?
    #if DEBUG
    var previewFeatureName: String?
    #endif

    let store: ConfigStore
    var git: ShellGitClient
    private let claudeJSON: URL
    private let scratchDir: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updateTask: Task<Void, Never>?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, checksDependencies: Bool = true,
         checksForUpdates: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        store = ConfigStore(paths: MWTPaths(home: home))
        git = ShellGitClient(gitPath: ToolEnvironment.fixed.findExecutable("git") ?? DependencyCheck.appleGitShim,
                             runner: ProcessRunner())
        claudeJSON = home.appending(path: ".claude.json")
        scratchDir = FileManager.default.temporaryDirectory.appending(path: "mwt-scratch")
        defaults.register(defaults: [Self.checkForUpdatesKey: true])
        skippedUpdateVersion = defaults.string(forKey: Self.skippedUpdateKey)
        reload()
        if checksDependencies { checkDependencies() }
        if checksForUpdates { startUpdateChecks() }
    }

    var gitReady: Bool {
        if case .checked(let report) = dependencies { return report.git.isReady }
        return false
    }

    var claudeAvailable: Bool {
        if case .checked(let report) = dependencies { return report.claudeInstalled }
        return false
    }

    var gitFooterText: String {
        guard case .checked(let report) = dependencies else { return "git · checking…" }
        if case .ready(let path, let version) = report.git { return "git \(version) · \(path)" }
        return "git · unavailable"
    }

    var pathFooter: (text: String, help: String)? {
        guard case .checked(let report) = dependencies else { return nil }
        switch report.environment.source {
        case .loginShell: return ("PATH · login shell", report.environment.path)
        case .fallback: return ("PATH · fallback", report.environment.path)
        case .fixed: return ("PATH · fixed", report.environment.path)
        }
    }

    func checkDependencies() {
        dependencies = .checking
        let claudeInstalled = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "claude://")!) != nil
        Task {
            let report = await Task.detached {
                let environment = ToolEnvironment.resolveFromLoginShell()
                return DependencyCheck(claudeInstalled: { claudeInstalled })
                    .run(environment: environment, runner: ProcessRunner(environment: environment))
            }.value
            apply(report)
        }
    }

    func apply(_ report: DependencyReport) {
        dependencies = .checked(report)
        if case .ready(let path, _) = report.git {
            git = ShellGitClient(gitPath: path, runner: ProcessRunner(environment: report.environment))
        }
    }

    func installCommandLineTools() {
        Task.detached {
            _ = try? ProcessRunner().run(DependencyCheck.xcodeSelect, ["--install"], cwd: nil, extraEnvironment: [:])
        }
    }

    func openClaudeDownloadPage() {
        NSWorkspace.shared.open(Self.claudeDownloadURL)
    }

    var visibleUpdate: AppVersion? {
        UpdateNotice.visible(status: update, skipped: skippedUpdateVersion, dismissed: updateDismissed)
    }

    var updateHelp: String {
        guard defaults.bool(forKey: Self.checkForUpdatesKey) else { return "Update checks are off" }
        switch update {
        case nil: return "Checking for updates…"
        case .upToDate?: return "Up to date"
        case .available(let version)?: return "MultiWorktree \(version) is available"
        case .failed(let reason)?: return "Update check failed: \(reason)"
        }
    }

    func startUpdateChecks() {
        guard updateTask == nil, let current = AppVersion(KitInfo.version) else { return }
        let session = URLSession(configuration: .ephemeral)
        let check = UpdateCheck(current: current, fetch: { try await session.data(for: $0) })
        let defaults = self.defaults
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                if defaults.bool(forKey: AppModel.checkForUpdatesKey) {
                    let status = await check.run()
                    guard let self else { return }
                    self.applyUpdate(status)
                }
                try? await Task.sleep(for: UpdateCheck.interval)
            }
        }
    }

    func applyUpdate(_ status: UpdateStatus) {
        update = status
        updateDismissed = false
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(UpdateCheck.releasesPage)
    }

    func dismissUpdate() {
        updateDismissed = true
    }

    func skipUpdate(_ version: AppVersion) {
        skippedUpdateVersion = version.description
        defaults.set(version.description, forKey: Self.skippedUpdateKey)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        guard result.succeeded else { throw OpenError(url: url, message: result.stderr) }
    }
}
