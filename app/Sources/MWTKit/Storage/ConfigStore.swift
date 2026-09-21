import Foundation

public struct ConfigStore: Sendable {
    public let paths: MWTPaths

    public init(paths: MWTPaths) {
        self.paths = paths
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public func loadGroups() throws -> GroupsFile {
        guard FileManager.default.fileExists(atPath: paths.groupsFile.path) else { return GroupsFile(groups: []) }
        return try Self.makeDecoder().decode(GroupsFile.self, from: Data(contentsOf: paths.groupsFile))
    }

    public func saveGroups(_ file: GroupsFile) throws {
        for group in file.groups { try group.validate() }
        try write(try Self.makeEncoder().encode(file), to: paths.groupsFile)
    }

    public func loadManifest(segment: String) throws -> FeatureManifest? {
        let url = paths.manifestURL(segment: segment)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.makeDecoder().decode(FeatureManifest.self, from: Data(contentsOf: url))
    }

    public func saveManifest(_ manifest: FeatureManifest) throws {
        try write(try Self.makeEncoder().encode(manifest), to: paths.manifestURL(segment: manifest.segment))
    }

    public func deleteManifest(segment: String) throws {
        let url = paths.manifestURL(segment: segment)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func listManifests() throws -> [FeatureManifest] {
        guard FileManager.default.fileExists(atPath: paths.featuresDir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: paths.featuresDir, includingPropertiesForKeys: nil)
        let decoder = Self.makeDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(FeatureManifest.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
