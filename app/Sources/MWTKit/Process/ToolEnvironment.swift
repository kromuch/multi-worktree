import Foundation

public struct ToolEnvironment: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case fixed
        case loginShell
        case fallback(reason: String)
    }

    public static let fixedPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    public static let fixed = ToolEnvironment(path: fixedPath, source: .fixed)

    public let path: String
    public let source: Source

    public init(path: String, source: Source) {
        self.path = path
        self.source = source
    }

    public var entries: [String] {
        path.split(separator: ":").map(String.init)
    }

    public func childEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["PATH"] = path
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        return env
    }

    public func findExecutable(_ name: String,
                               isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        for entry in entries {
            let candidate = URL(fileURLWithPath: entry).appending(path: name).path
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}

public enum ToolPath {
    public static func merge(primary: [String], fallback: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for entry in primary + fallback {
            let normalized = normalize(entry)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            merged.append(normalized)
        }
        return merged
    }

    static func normalize(_ entry: String) -> String {
        var value = entry
        while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
        return value
    }
}
