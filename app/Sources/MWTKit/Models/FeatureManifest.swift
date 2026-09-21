import Foundation

public enum RepoStatus: String, Codable, Sendable {
    case created
    case reused
    case failed
    case removed
}

public struct ManifestRepo: Codable, Equatable, Sendable {
    public var path: String
    public var worktree: String
    public var isMain: Bool
    public var remote: String?
    public var defaultBranch: String?
    public var baseRef: String?
    public var branchCreated: Bool
    public var status: RepoStatus

    public init(path: String, worktree: String, isMain: Bool, remote: String?, defaultBranch: String?,
                baseRef: String?, branchCreated: Bool, status: RepoStatus) {
        self.path = path
        self.worktree = worktree
        self.isMain = isMain
        self.remote = remote
        self.defaultBranch = defaultBranch
        self.baseRef = baseRef
        self.branchCreated = branchCreated
        self.status = status
    }
}

public struct FeatureManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var feature: String
    public var segment: String
    public var group: String
    public var createdAt: Date
    public var mainWorktree: String
    public var repos: [ManifestRepo]
    public var denyEntries: [String]

    public init(feature: String, segment: String, group: String, createdAt: Date, mainWorktree: String,
                repos: [ManifestRepo], denyEntries: [String]) {
        self.version = 1
        self.feature = feature
        self.segment = segment
        self.group = group
        self.createdAt = createdAt
        self.mainWorktree = mainWorktree
        self.repos = repos
        self.denyEntries = denyEntries
    }

    public var managedAdditionalDirectories: [String] {
        repos.filter { !$0.isMain && ($0.status == .created || $0.status == .reused) }.map(\.worktree)
    }

    public func managedAdditionalDirectories(inGroupSiblingPaths siblingPaths: [String]) -> [String] {
        repos.filter { repo in
            guard !repo.isMain, repo.status == .created || repo.status == .reused else { return false }
            return siblingPaths.contains { PathCompare.same($0, repo.path) }
        }.map(\.worktree)
    }

    public var allRemoved: Bool {
        repos.allSatisfy { $0.status == .removed }
    }

    public func repoIndex(path: String) -> Int? {
        repos.firstIndex { $0.path == path }
    }
}
