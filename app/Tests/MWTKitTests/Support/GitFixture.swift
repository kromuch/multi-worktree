import Foundation
import Testing
@testable import MWTKit

struct GitFixture {
    static let environment: [String: String] = [
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.com",
    ]

    let root: URL
    let remote: URL
    let repo: URL
    let git: ShellGitClient

    static func makeClient() throws -> ShellGitClient {
        let gitPath = try #require(ToolEnvironment.resolveGit())
        return ShellGitClient(gitPath: gitPath, runner: ProcessRunner(), baseEnvironment: environment)
    }

    init(name: String = "repo", root: URL? = nil) throws {
        self.root = try root ?? TempDir.make()
        git = try Self.makeClient()
        remote = self.root.appending(path: "\(name)-remote.git")
        repo = self.root.appending(path: name)
        try git.run(["init", "--quiet", "--bare", "--initial-branch=main", remote.path])
        try git.run(["clone", "--quiet", remote.path, repo.path])
        try git.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: repo)
        try commit(file: "README.md", content: "hello\n", message: "init")
        try git.run(["push", "--quiet", "-u", "origin", "main"], in: repo)
        try git.run(["remote", "set-head", "origin", "--auto"], in: repo)
    }

    @discardableResult
    func commit(file: String, content: String, message: String, in directory: URL? = nil) throws -> String {
        let target = directory ?? repo
        let url = target.appending(path: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        try git.run(["add", file], in: target)
        try git.run(["commit", "--quiet", "-m", message], in: target)
        return try git.run(["rev-parse", "HEAD"], in: target)
    }
}
