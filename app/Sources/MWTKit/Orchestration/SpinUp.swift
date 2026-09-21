import Foundation

public struct SpinUpRequest: Sendable {
    public var group: RepoGroup
    public var feature: FeatureName
    public var baseChoices: [String: BaseChoice]
    public var openClaude: Bool

    public init(group: RepoGroup, feature: FeatureName, baseChoices: [String: BaseChoice], openClaude: Bool) {
        self.group = group
        self.feature = feature
        self.baseChoices = baseChoices
        self.openClaude = openClaude
    }
}

public struct SpinUpEnvironment: Sendable {
    public var git: any GitClient
    public var store: ConfigStore
    public var claudeJSON: URL
    public var scratchDir: URL
    public var open: @Sendable (URL) throws -> Void
    public var now: @Sendable () -> Date

    public init(git: any GitClient, store: ConfigStore, claudeJSON: URL, scratchDir: URL,
                open: @escaping @Sendable (URL) throws -> Void, now: @escaping @Sendable () -> Date) {
        self.git = git
        self.store = store
        self.claudeJSON = claudeJSON
        self.scratchDir = scratchDir
        self.open = open
        self.now = now
    }
}

public enum SpinUpError: Error, Equatable, Sendable {
    case invalidGroup(String)
    case featureUsedByOtherGroup(feature: String, group: String)
    case segmentCollision(segment: String, feature: String)
    case targetPathOccupied(String)
}

enum PathCompare {
    static func same(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).resolvingSymlinksInPath().path == URL(fileURLWithPath: b).resolvingSymlinksInPath().path
    }
}

func describe(_ error: any Error) -> String {
    if let gitError = error as? GitError {
        return "git \(gitError.arguments.joined(separator: " ")) failed (\(gitError.status)): \(gitError.stderr)"
    }
    return String(describing: error)
}

public struct SpinUp: Sendable {
    public let env: SpinUpEnvironment

    public init(env: SpinUpEnvironment) {
        self.env = env
    }

    public func run(_ request: SpinUpRequest,
                    preflights: [String: Result<RepoPreflight, PreflightError>]) throws -> (manifest: FeatureManifest, report: RunReport) {
        do { try request.group.validate() } catch { throw SpinUpError.invalidGroup(String(describing: error)) }
        let feature = request.feature
        let paths = env.store.paths
        let main = request.group.main!

        let existing = try env.store.loadManifest(segment: feature.segment)
        if let existing {
            guard existing.feature == feature.branch else {
                throw SpinUpError.segmentCollision(segment: feature.segment, feature: existing.feature)
            }
            guard existing.group == request.group.name else {
                throw SpinUpError.featureUsedByOtherGroup(feature: feature.branch, group: existing.group)
            }
        }
        var manifest = existing ?? FeatureManifest(
            feature: feature.branch, segment: feature.segment, group: request.group.name, createdAt: env.now(),
            mainWorktree: paths.worktreeURL(segment: feature.segment, basename: main.basename).path,
            repos: [], denyEntries: [])
        let previousAdditional = manifest.managedAdditionalDirectories
        let previousDeny = manifest.denyEntries
        var report = RunReport()

        for repo in request.group.repos {
            let worktree = paths.worktreeURL(segment: feature.segment, basename: repo.basename)
            var entry = ManifestRepo(path: repo.path, worktree: worktree.path, isMain: repo.isMain, remote: nil,
                                     defaultBranch: nil, baseRef: nil, branchCreated: false, status: .failed)
            if let index = manifest.repoIndex(path: repo.path) {
                entry = manifest.repos[index]
                entry.worktree = worktree.path
                entry.isMain = repo.isMain
            }
            switch preflights[repo.path] {
            case .success(let preflight)?:
                entry.remote = preflight.remote
                entry.defaultBranch = preflight.defaultBranch
                do {
                    let choice = request.baseChoices[repo.path] ?? .defaultBranch
                    report.outcomes.append(try provision(repo: repo, preflight: preflight, worktree: worktree,
                                                         feature: feature, choice: choice, entry: &entry))
                } catch {
                    entry.status = .failed
                    report.outcomes.append(RepoOutcome(repoPath: repo.path, label: .failed, reasons: [describe(error)]))
                }
            case .failure(let error)?:
                entry.status = .failed
                report.outcomes.append(RepoOutcome(repoPath: repo.path, label: .failed, reasons: ["pre-flight failed: \(error)"]))
            case nil:
                entry.status = .failed
                report.outcomes.append(RepoOutcome(repoPath: repo.path, label: .failed, reasons: ["no pre-flight result"]))
            }
            if let index = manifest.repoIndex(path: repo.path) {
                manifest.repos[index] = entry
            } else {
                manifest.repos.append(entry)
            }
            try env.store.saveManifest(manifest)
        }

        guard let mainEntry = manifest.repos.first(where: { $0.isMain }),
              mainEntry.status == .created || mainEntry.status == .reused else {
            report.hardError = "main repo \(main.path) could not be provisioned; wiring and Claude launch skipped"
            return (manifest, report)
        }

        let mainWorktree = URL(fileURLWithPath: mainEntry.worktree)
        let denyEntries = request.group.siblings.flatMap { DenyRules.rules(forOriginal: $0.path) }
        let grantedAdditional = manifest.managedAdditionalDirectories(inGroupSiblingPaths: request.group.siblings.map(\.path))
        let update = LocalSettingsUpdate(
            additionalDirectoriesToRemove: previousAdditional,
            additionalDirectoriesToAdd: grantedAdditional,
            denyToRemove: previousDeny,
            denyToAdd: denyEntries)
        if try LocalSettings.write(update, at: mainWorktree.appending(path: ".claude/settings.local.json")) {
            report.notes.append("settings.local.json was not valid JSON; backed up to .bak and recreated")
        }
        manifest.denyEntries = denyEntries

        let added = try GitExclude.ensure(in: try env.git.commonDir(of: URL(fileURLWithPath: main.path)))
        if !added.isEmpty { report.notes.append("added to info/exclude: \(added.joined(separator: ", "))") }

        let failedSiblings = manifest.repos
            .filter { !$0.isMain && $0.status == .failed }
            .map { URL(fileURLWithPath: $0.path).lastPathComponent }
        let rules = RulesFile.render(RulesFileContext(
            feature: feature.branch, mainRepoName: main.basename,
            siblingWorktrees: grantedAdditional, unavailableSiblings: failedSiblings))
        try rules.write(to: mainWorktree.appending(path: RulesFile.fileName), atomically: true, encoding: .utf8)

        if ClaudeUserState.hasLocalMCPServers(forProject: main.path, claudeJSON: env.claudeJSON) {
            report.notes.append("local-scope MCP servers of \(main.path) are not available in the worktree; move them to project-scope .mcp.json")
        }
        try env.store.saveManifest(manifest)

        if request.openClaude {
            if failedSiblings.isEmpty {
                try env.open(DeepLink.newSession(folder: mainWorktree))
                report.openedClaude = true
            } else {
                report.notes.append("Claude not opened: \(failedSiblings.count) sibling(s) failed; use Open Claude anyway")
            }
        }
        return (manifest, report)
    }

    private func provision(repo: RepoEntry, preflight: RepoPreflight, worktree: URL, feature: FeatureName,
                           choice: BaseChoice, entry: inout ManifestRepo) throws -> RepoOutcome {
        let original = URL(fileURLWithPath: repo.path)
        let fm = FileManager.default
        env.git.worktreePrune(in: original)
        if fm.fileExists(atPath: worktree.path) {
            let registered = try env.git.worktrees(in: original).first { PathCompare.same($0.path, worktree.path) }
            if let registered, registered.branch == feature.branch {
                entry.status = .reused
                return RepoOutcome(repoPath: repo.path, label: .reused, reasons: ["worktree already exists on branch \(feature.branch)"])
            }
            if !((try? fm.contentsOfDirectory(atPath: worktree.path)) ?? []).isEmpty {
                throw SpinUpError.targetPathOccupied(worktree.path)
            }
        }
        var reasons: [String] = []
        let base = BaseDecision.baseRef(for: preflight, choice: choice)
        if let warning = base.warning { reasons.append(warning) }
        let plan = BranchResolution.plan(feature: feature.branch, preflight: preflight, baseRef: base.ref)
        try fm.createDirectory(at: worktree.deletingLastPathComponent(), withIntermediateDirectories: true)
        try env.git.worktreeAdd(plan, at: worktree, in: original)
        switch plan {
        case .reuseLocal(let branch):
            entry.baseRef = branch
            entry.branchCreated = false
            reasons.append("reused existing local branch \(branch)")
        case .trackRemote(let remote, let branch):
            entry.baseRef = "\(remote)/\(branch)"
            entry.branchCreated = false
            reasons.append("tracking \(remote)/\(branch)")
        case .createNew(let branch, let baseRef):
            entry.baseRef = baseRef
            entry.branchCreated = true
            reasons.append("new branch \(branch) from \(baseRef)")
        }
        let files = try WorktreeInclude.filesToCopy(git: env.git, original: original, scratchDir: env.scratchDir)
        if !files.isEmpty {
            try WorktreeInclude.copy(files, from: original, to: worktree)
            reasons.append("copied \(files.count) .worktreeinclude file(s)")
        }
        entry.status = .created
        return RepoOutcome(repoPath: repo.path, label: .created, reasons: reasons)
    }
}
