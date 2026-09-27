import Foundation
import Testing

@Suite struct VersionPolicyTests {
    struct Output {
        let status: Int32
        let text: String
    }

    static let checkout = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let environment: [String: String] = [
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": NSTemporaryDirectory(),
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.com",
    ]

    static let kitInfo = "app/Sources/MWTKit/KitInfo.swift"
    static let fixText = "app/scripts/bump-version.sh && git add app/Sources/MWTKit/KitInfo.swift"

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], in directory: URL) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    static func git(_ arguments: String..., in repo: URL) throws -> Output {
        try run("/usr/bin/env", ["git"] + arguments, in: repo)
    }

    static func setVersion(_ version: String, in repo: URL) throws {
        try "public enum KitInfo {\n    public static let version = \"\(version)\"\n}\n"
            .write(to: repo.appending(path: kitInfo), atomically: true, encoding: .utf8)
    }

    static func version(in repo: URL) throws -> String {
        let text = try String(contentsOf: repo.appending(path: kitInfo), encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.contains("version = ") })
        return String(line.split(separator: "\"")[1])
    }

    static func commitFile(_ name: String, in repo: URL) throws -> Output {
        try name.write(to: repo.appending(path: name), atomically: true, encoding: .utf8)
        try git("add", "-A", in: repo)
        return try git("commit", "-q", "-m", "add \(name)", in: repo)
    }

    static func bump(_ arguments: [String] = [], in repo: URL) throws -> Output {
        try run(repo.appending(path: "app/scripts/bump-version.sh").path, arguments, in: repo)
    }

    static func makeRepo(version: String = "0.1.0") throws -> URL {
        let repo = try TempDir.make().appending(path: "repo")
        let fm = FileManager.default
        for dir in [".githooks", "app/scripts", "app/Sources/MWTKit"] {
            try fm.createDirectory(at: repo.appending(path: dir), withIntermediateDirectories: true)
        }
        for file in [".githooks/pre-commit", ".githooks/version-lib.sh", "app/scripts/bump-version.sh"] {
            try fm.copyItem(at: checkout.appending(path: file), to: repo.appending(path: file))
        }
        try setVersion(version, in: repo)
        try git("init", "-q", "-b", "main", in: repo)
        try git("config", "core.hooksPath", ".githooks", in: repo)
        try git("add", "-A", in: repo)
        let initial = try git("commit", "-q", "-m", "init", in: repo)
        #expect(initial.status == 0, "\(initial.text)")
        return repo
    }

    static func publishHead(in repo: URL) throws {
        try git("update-ref", "refs/remotes/origin/main", "HEAD", in: repo)
    }

    @Test func commitOnMainWithoutOriginIsAllowed() throws {
        let repo = try Self.makeRepo()
        let result = try Self.commitFile("a.txt", in: repo)
        #expect(result.status == 0, "\(result.text)")
    }

    @Test func unbumpedCommitIsRejectedAndTheSuggestedFixWorks() throws {
        let repo = try Self.makeRepo()
        try Self.publishHead(in: repo)
        let rejected = try Self.commitFile("a.txt", in: repo)
        #expect(rejected.status != 0)
        #expect(rejected.text.contains("version 0.1.0 is not newer than origin/main (0.1.0)"), "\(rejected.text)")
        #expect(rejected.text.contains(Self.fixText), "\(rejected.text)")

        #expect(try Self.bump(in: repo).status == 0)
        try Self.git("add", Self.kitInfo, in: repo)
        let accepted = try Self.git("commit", "-q", "-m", "add a.txt", in: repo)
        #expect(accepted.status == 0, "\(accepted.text)")
        #expect(try Self.version(in: repo) == "0.1.1")
    }

    @Test func lowerVersionIsRejected() throws {
        let repo = try Self.makeRepo()
        try Self.publishHead(in: repo)
        try Self.setVersion("0.0.9", in: repo)
        let result = try Self.commitFile("a.txt", in: repo)
        #expect(result.status != 0)
        #expect(result.text.contains("version 0.0.9 is not newer than origin/main (0.1.0)"), "\(result.text)")
    }

    @Test func oneBumpCoversLaterCommits() throws {
        let repo = try Self.makeRepo()
        try Self.publishHead(in: repo)
        try Self.setVersion("0.1.1", in: repo)
        let first = try Self.commitFile("a.txt", in: repo)
        #expect(first.status == 0, "\(first.text)")
        let second = try Self.commitFile("b.txt", in: repo)
        #expect(second.status == 0, "\(second.text)")
    }

    @Test func featureBranchWithoutRemoteComparesWithMain() throws {
        let repo = try Self.makeRepo()
        try Self.git("switch", "-q", "-c", "feature/x", in: repo)
        let rejected = try Self.commitFile("a.txt", in: repo)
        #expect(rejected.status != 0)
        #expect(rejected.text.contains("is not newer than main (0.1.0)"), "\(rejected.text)")
        try Self.setVersion("0.1.1", in: repo)
        try Self.git("add", "-A", in: repo)
        let accepted = try Self.git("commit", "-q", "-m", "add a.txt", in: repo)
        #expect(accepted.status == 0, "\(accepted.text)")
    }

    @Test func bumpScriptIncrementsEachPart() throws {
        let repo = try Self.makeRepo(version: "0.1.0")
        let patch = try Self.bump(in: repo)
        #expect(patch.text.trimmingCharacters(in: .whitespacesAndNewlines) == "0.1.0 -> 0.1.1")
        #expect(try Self.version(in: repo) == "0.1.1")
        #expect(try Self.bump(["minor"], in: repo).text.contains("0.1.1 -> 0.2.0"))
        #expect(try Self.bump(["major"], in: repo).text.contains("0.2.0 -> 1.0.0"))
        #expect(try Self.version(in: repo) == "1.0.0")
        #expect(try Self.bump(["huge"], in: repo).status == 2)
        #expect(try Self.version(in: repo) == "1.0.0")
    }

    @Test func bumpStartsFromOriginMainWhenItIsHigher() throws {
        let repo = try Self.makeRepo(version: "0.1.5")
        try Self.publishHead(in: repo)
        try Self.setVersion("0.1.1", in: repo)
        let result = try Self.bump(in: repo)
        #expect(result.text.contains("0.1.1 -> 0.1.6"), "\(result.text)")
        #expect(try Self.version(in: repo) == "0.1.6")
    }

    @Test func hookFailsClosedWithoutTheLibrary() throws {
        let repo = try Self.makeRepo()
        try Self.publishHead(in: repo)
        try FileManager.default.removeItem(at: repo.appending(path: ".githooks/version-lib.sh"))
        try Self.setVersion("0.1.1", in: repo)
        let result = try Self.commitFile("a.txt", in: repo)
        #expect(result.status != 0)
        #expect(result.text.contains("version-lib.sh is missing"), "\(result.text)")
    }
}
