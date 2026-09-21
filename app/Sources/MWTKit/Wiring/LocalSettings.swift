import Foundation

public struct LocalSettingsUpdate: Sendable {
    public var additionalDirectoriesToRemove: [String]
    public var additionalDirectoriesToAdd: [String]
    public var denyToRemove: [String]
    public var denyToAdd: [String]

    public init(additionalDirectoriesToRemove: [String], additionalDirectoriesToAdd: [String],
                denyToRemove: [String], denyToAdd: [String]) {
        self.additionalDirectoriesToRemove = additionalDirectoriesToRemove
        self.additionalDirectoriesToAdd = additionalDirectoriesToAdd
        self.denyToRemove = denyToRemove
        self.denyToAdd = denyToAdd
    }
}

public enum LocalSettings {
    public struct Outcome: Equatable, Sendable {
        public let data: Data
        public let recreated: Bool
    }

    public static func apply(_ update: LocalSettingsUpdate, to existing: Data?) throws -> Outcome {
        var root: [String: Any] = [:]
        var recreated = false
        if let existing, !existing.isEmpty {
            if let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] {
                root = parsed
            } else {
                recreated = true
            }
        }
        var permissions = root["permissions"] as? [String: Any] ?? [:]
        permissions["additionalDirectories"] = merge(permissions["additionalDirectories"],
                                                     remove: update.additionalDirectoriesToRemove,
                                                     add: update.additionalDirectoriesToAdd)
        permissions["deny"] = merge(permissions["deny"], remove: update.denyToRemove, add: update.denyToAdd)
        root["permissions"] = permissions
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return Outcome(data: data, recreated: recreated)
    }

    @discardableResult
    public static func write(_ update: LocalSettingsUpdate, at fileURL: URL) throws -> Bool {
        let fm = FileManager.default
        let existing = fm.fileExists(atPath: fileURL.path) ? try Data(contentsOf: fileURL) : nil
        let outcome = try apply(update, to: existing)
        if outcome.recreated, let existing {
            try existing.write(to: fileURL.appendingPathExtension("bak"), options: .atomic)
        }
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try outcome.data.write(to: fileURL, options: .atomic)
        return outcome.recreated
    }

    static func merge(_ existing: Any?, remove: [String], add: [String]) -> [String] {
        var list = existing as? [String] ?? []
        list.removeAll { remove.contains($0) }
        for item in add where !list.contains(item) { list.append(item) }
        return list
    }
}
