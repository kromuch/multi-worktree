import Foundation

public enum GroupValidationError: Error, Equatable, Sendable {
    case emptyName
    case noRepos
    case noMain
    case multipleMains
    case relativePath(String)
    case duplicateBasename(String)
}

public struct RepoEntry: Codable, Equatable, Sendable {
    public var path: String
    public var isMain: Bool

    public init(path: String, isMain: Bool) {
        self.path = path
        self.isMain = isMain
    }

    public var basename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

public struct RepoGroup: Codable, Equatable, Sendable {
    public var name: String
    public var repos: [RepoEntry]

    public init(name: String, repos: [RepoEntry]) {
        self.name = name
        self.repos = repos
    }

    public var main: RepoEntry? {
        repos.first { $0.isMain }
    }

    public var siblings: [RepoEntry] {
        repos.filter { !$0.isMain }
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw GroupValidationError.emptyName }
        guard !repos.isEmpty else { throw GroupValidationError.noRepos }
        let mains = repos.filter { $0.isMain }
        guard !mains.isEmpty else { throw GroupValidationError.noMain }
        guard mains.count == 1 else { throw GroupValidationError.multipleMains }
        var seen = Set<String>()
        for repo in repos {
            guard repo.path.hasPrefix("/") else { throw GroupValidationError.relativePath(repo.path) }
            guard seen.insert(repo.basename).inserted else { throw GroupValidationError.duplicateBasename(repo.basename) }
        }
    }
}

public struct GroupsFile: Codable, Equatable, Sendable {
    public var version: Int
    public var groups: [RepoGroup]

    public init(groups: [RepoGroup]) {
        self.version = 1
        self.groups = groups
    }
}
