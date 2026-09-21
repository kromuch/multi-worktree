import Foundation

enum TempDir {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "mwt-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
