import Foundation

public struct MWTPaths: Sendable {
    public let root: URL

    public init(home: URL) {
        root = home.appending(path: ".mwt")
    }

    public var groupsFile: URL { root.appending(path: "groups.json") }
    public var featuresDir: URL { root.appending(path: "features") }
    public var treesDir: URL { root.appending(path: "trees") }

    public func manifestURL(segment: String) -> URL {
        featuresDir.appending(path: "\(segment).json")
    }

    public func treeDir(segment: String) -> URL {
        treesDir.appending(path: segment)
    }

    public func worktreeURL(segment: String, basename: String) -> URL {
        treeDir(segment: segment).appending(path: basename)
    }
}
