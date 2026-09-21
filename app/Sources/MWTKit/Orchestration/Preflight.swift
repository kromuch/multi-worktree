import Foundation
import Synchronization

public enum BaseChoice: String, Sendable {
    case defaultBranch
    case currentBranch
}

public enum PreflightError: Error, Equatable, Sendable {
    case unreadable(String)
    case invalidBranchName(String)
    case notARepository(String)
    case pathIsNotRepoRoot(path: String, root: String)
    case noDefaultBranch(String)
}

public struct RepoPreflight: Equatable, Sendable {
    public let repo: RepoEntry
    public let commonDir: String
    public let remote: String
    public let hasRemote: Bool
    public let defaultBranch: String
    public let currentBranch: String?
    public let remoteDefaultExists: Bool
    public let localFeatureBranchExists: Bool
    public let remoteFeatureBranchExists: Bool
    public let notices: [String]

    public var offersCurrentBranchBase: Bool {
        guard let currentBranch else { return false }
        return currentBranch != defaultBranch
    }
}

public enum BaseDecision {
    public static func baseRef(for p: RepoPreflight, choice: BaseChoice) -> (ref: String, warning: String?) {
        switch choice {
        case .currentBranch:
            if p.offersCurrentBranchBase, let current = p.currentBranch { return (current, nil) }
            return defaultRef(p, prefix: "current branch not available as a base")
        case .defaultBranch:
            return defaultRef(p, prefix: nil)
        }
    }

    static func defaultRef(_ p: RepoPreflight, prefix: String?) -> (ref: String, warning: String?) {
        if p.remoteDefaultExists {
            return ("\(p.remote)/\(p.defaultBranch)", prefix.map { "\($0); using \(p.remote)/\(p.defaultBranch)" })
        }
        let fallback = "\(p.remote)/\(p.defaultBranch) unavailable; based on local \(p.defaultBranch)"
        return (p.defaultBranch, [prefix, fallback].compactMap { $0 }.joined(separator: "; "))
    }
}

public enum BranchResolution {
    public static func plan(feature: String, preflight p: RepoPreflight, baseRef: String) -> WorktreeBranchPlan {
        if p.localFeatureBranchExists { return .reuseLocal(feature) }
        if p.remoteFeatureBranchExists { return .trackRemote(remote: p.remote, branch: feature) }
        return .createNew(branch: feature, base: baseRef)
    }
}

public struct Preflight: Sendable {
    public let git: any GitClient

    public init(git: any GitClient) {
        self.git = git
    }

    public func runAll(group: RepoGroup, feature: FeatureName) -> [String: Result<RepoPreflight, PreflightError>] {
        let repos = group.repos
        let collected = Mutex<[String: Result<RepoPreflight, PreflightError>]>([:])
        DispatchQueue.concurrentPerform(iterations: repos.count) { index in
            let repo = repos[index]
            let result: Result<RepoPreflight, PreflightError>
            do {
                result = .success(try run(repo: repo, feature: feature))
            } catch let error as PreflightError {
                result = .failure(error)
            } catch {
                result = .failure(.notARepository(repo.path))
            }
            collected.withLock { $0[repo.path] = result }
        }
        return collected.withLock { $0 }
    }

    public func run(repo: RepoEntry, feature: FeatureName) throws -> RepoPreflight {
        let dir = URL(fileURLWithPath: repo.path)
        guard FileManager.default.isReadableFile(atPath: repo.path) else { throw PreflightError.unreadable(repo.path) }
        guard git.isValidBranchName(feature.branch) else { throw PreflightError.invalidBranchName(feature.branch) }
        guard let top = try? git.topLevel(of: dir) else { throw PreflightError.notARepository(repo.path) }
        guard top.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path else {
            throw PreflightError.pathIsNotRepoRoot(path: repo.path, root: top.path)
        }
        let commonDir = try git.commonDir(of: dir)
        let current = git.currentBranch(in: dir)
        let remotes = try git.remotes(in: dir)
        var notices: [String] = []

        let remote = current.flatMap { git.configuredRemote(forBranch: $0, in: dir) }
            ?? (remotes.count == 1 ? remotes[0] : "origin")
        let hasRemote = remotes.contains(remote)
        if !hasRemote { notices.append("no remote configured") }
        let fetched = hasRemote ? git.fetch(remote: remote, in: dir) : false
        if hasRemote, !fetched { notices.append("fetch from \(remote) failed; using cached refs") }

        var defaultBranch = hasRemote ? git.remoteHead(remote: remote, in: dir) : nil
        if defaultBranch == nil, hasRemote, git.setRemoteHeadAuto(remote: remote, in: dir) {
            defaultBranch = git.remoteHead(remote: remote, in: dir)
        }
        if defaultBranch == nil {
            defaultBranch = ["main", "master"].first { git.localBranchExists($0, in: dir) }
        }
        guard let defaultBranch else { throw PreflightError.noDefaultBranch(repo.path) }

        let remoteDefaultExists = hasRemote && git.commitExists("\(remote)/\(defaultBranch)", in: dir)
        if !(try git.statusLines(in: dir)).isEmpty { notices.append("uncommitted changes in the original checkout") }
        if remoteDefaultExists, let ahead = git.revListCount("\(remote)/\(defaultBranch)..\(defaultBranch)", in: dir), ahead > 0 {
            notices.append("local \(defaultBranch) is \(ahead) commit(s) ahead of \(remote)/\(defaultBranch); the worktree is based on the remote tip")
        }
        if let current, current != defaultBranch, let upstream = git.upstream(of: current, in: dir) {
            if let ahead = git.revListCount("\(upstream)..\(current)", in: dir), ahead > 0 { notices.append("\(current) is \(ahead) commit(s) ahead of \(upstream)") }
            if let behind = git.revListCount("\(current)..\(upstream)", in: dir), behind > 0 { notices.append("\(current) is \(behind) commit(s) behind \(upstream)") }
        }
        let localFeature = git.localBranchExists(feature.branch, in: dir)
        if localFeature { notices.append("branch \(feature.branch) already exists and will be reused") }
        let remoteFeature = hasRemote && git.commitExists("\(remote)/\(feature.branch)", in: dir)
        if remoteFeature, !localFeature { notices.append("\(remote)/\(feature.branch) exists; a tracking worktree will be created") }

        return RepoPreflight(repo: repo, commonDir: commonDir.path, remote: remote, hasRemote: hasRemote,
                             defaultBranch: defaultBranch, currentBranch: current,
                             remoteDefaultExists: remoteDefaultExists, localFeatureBranchExists: localFeature,
                             remoteFeatureBranchExists: remoteFeature, notices: notices)
    }
}
