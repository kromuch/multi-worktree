import Foundation

public struct BranchState: Equatable, Sendable {
    public let localExists: Bool
    public let remoteBranchExists: Bool
    public let aheadOfRemote: Int?
    public let aheadOfDefault: Int?

    public init(localExists: Bool, remoteBranchExists: Bool, aheadOfRemote: Int?, aheadOfDefault: Int?) {
        self.localExists = localExists
        self.remoteBranchExists = remoteBranchExists
        self.aheadOfRemote = aheadOfRemote
        self.aheadOfDefault = aheadOfDefault
    }
}

public enum BranchDeletionDecision: Equatable, Sendable {
    case delete(reason: String)
    case keep(reason: String)
    case alreadyGone
}

public enum TearDownRules {
    public static func decide(_ state: BranchState) -> BranchDeletionDecision {
        guard state.localExists else { return .alreadyGone }
        if state.remoteBranchExists, state.aheadOfRemote == 0 { return .delete(reason: "fully pushed") }
        if state.aheadOfDefault == 0 { return .delete(reason: "no commits beyond the default branch") }
        if state.remoteBranchExists { return .keep(reason: "unpushed commits") }
        if state.aheadOfDefault == nil { return .keep(reason: "no remote branch and the default-branch check was unavailable") }
        return .keep(reason: "unpushed commits (no remote branch)")
    }
}

public enum TearDownError: Error, Equatable, Sendable {
    case noManifest(String)
}

public struct TearDownRequest: Sendable {
    public var segment: String
    public var discardConfirmedRepoPaths: Set<String>

    public init(segment: String, discardConfirmedRepoPaths: Set<String>) {
        self.segment = segment
        self.discardConfirmedRepoPaths = discardConfirmedRepoPaths
    }
}

public struct TearDown: Sendable {
    public let git: any GitClient
    public let store: ConfigStore

    public init(git: any GitClient, store: ConfigStore) {
        self.git = git
        self.store = store
    }

    public func run(_ request: TearDownRequest) throws -> (manifest: FeatureManifest?, report: RunReport) {
        guard var manifest = try store.loadManifest(segment: request.segment) else {
            throw TearDownError.noManifest(request.segment)
        }
        var report = RunReport()
        let fm = FileManager.default

        for index in manifest.repos.indices where manifest.repos[index].status != .removed {
            let repo = manifest.repos[index]
            let original = URL(fileURLWithPath: repo.path)
            let worktree = URL(fileURLWithPath: repo.worktree)
            var reasons: [String] = []

            git.worktreePrune(in: original)
            let registered = ((try? git.worktrees(in: original)) ?? []).contains { PathCompare.same($0.path, worktree.path) }
            if !fm.fileExists(atPath: worktree.path) || !registered {
                reasons.append("already removed")
            } else {
                let dirty = (try? git.statusLines(in: worktree)) ?? ["(git status failed)"]
                if !dirty.isEmpty, !request.discardConfirmedRepoPaths.contains(repo.path) {
                    let summary = ["uncommitted changes (\(dirty.count) entries)"] + dirty.prefix(10)
                    report.outcomes.append(RepoOutcome(repoPath: repo.path, label: .kept, reasons: summary))
                    continue
                }
                do {
                    try git.worktreeRemove(worktree, force: !dirty.isEmpty, in: original)
                    git.worktreePrune(in: original)
                    reasons.append(dirty.isEmpty ? "worktree removed" : "worktree removed (changes discarded)")
                } catch {
                    report.outcomes.append(RepoOutcome(repoPath: repo.path, label: .kept, reasons: ["worktree remove failed: \(describe(error))"]))
                    continue
                }
            }

            let (remote, defaultBranch) = resolveRemoteAndDefault(repo, original: original)
            let state = branchState(feature: manifest.feature, remote: remote, defaultBranch: defaultBranch, in: original)
            switch TearDownRules.decide(state) {
            case .alreadyGone:
                reasons.append("branch already gone")
            case .keep(let why):
                reasons.append("branch kept: \(why)")
            case .delete(let why):
                do {
                    try git.deleteBranch(manifest.feature, in: original)
                    reasons.append("branch deleted: \(why)")
                } catch {
                    reasons.append("branch delete failed: \(describe(error))")
                }
            }
            manifest.repos[index].status = .removed
            try store.saveManifest(manifest)
            report.outcomes.append(RepoOutcome(repoPath: repo.path, label: .removed, reasons: reasons))
        }

        report.notes.append("Claude tabs stay open; a session whose folder is gone resumes in its launch directory.")
        if manifest.allRemoved {
            let treeDir = store.paths.treeDir(segment: manifest.segment)
            if let contents = try? fm.contentsOfDirectory(atPath: treeDir.path), contents.isEmpty {
                try? fm.removeItem(at: treeDir)
            }
            try store.deleteManifest(segment: manifest.segment)
            return (nil, report)
        }
        return (manifest, report)
    }

    func resolveRemoteAndDefault(_ repo: ManifestRepo, original: URL) -> (String?, String?) {
        if let remote = repo.remote, let defaultBranch = repo.defaultBranch { return (remote, defaultBranch) }
        let remotes = (try? git.remotes(in: original)) ?? []
        let remote: String? = remotes.count == 1 ? remotes[0] : (remotes.contains("origin") ? "origin" : remotes.first)
        let defaultBranch = remote.flatMap { git.remoteHead(remote: $0, in: original) }
            ?? ["main", "master"].first { git.localBranchExists($0, in: original) }
        return (remote, defaultBranch)
    }

    func branchState(feature: String, remote: String?, defaultBranch: String?, in original: URL) -> BranchState {
        guard git.localBranchExists(feature, in: original) else {
            return BranchState(localExists: false, remoteBranchExists: false, aheadOfRemote: nil, aheadOfDefault: nil)
        }
        guard let remote, ((try? git.remotes(in: original)) ?? []).contains(remote) else {
            return BranchState(localExists: true, remoteBranchExists: false, aheadOfRemote: nil, aheadOfDefault: nil)
        }
        _ = git.fetch(remote: remote, in: original)
        let remoteExists = git.commitExists("\(remote)/\(feature)", in: original)
        let aheadOfRemote = remoteExists ? git.revListCount("\(remote)/\(feature)..\(feature)", in: original) : nil
        let aheadOfDefault = defaultBranch.flatMap { git.revListCount("\(remote)/\($0)..\(feature)", in: original) }
        return BranchState(localExists: true, remoteBranchExists: remoteExists, aheadOfRemote: aheadOfRemote, aheadOfDefault: aheadOfDefault)
    }
}
