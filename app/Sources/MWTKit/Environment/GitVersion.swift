import Foundation

public struct GitVersion: Comparable, Sendable, CustomStringConvertible {
    public static let minimum = GitVersion(major: 2, minor: 31, patch: 0)

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func parse(_ output: String) -> GitVersion? {
        let prefix = "git version "
        guard let line = output.split(separator: "\n").first, line.hasPrefix(prefix),
              let token = line.dropFirst(prefix.count).split(separator: " ").first else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        let patch = parts.count > 2 ? Int(parts[2].prefix { $0.isNumber }) ?? 0 : 0
        return GitVersion(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
