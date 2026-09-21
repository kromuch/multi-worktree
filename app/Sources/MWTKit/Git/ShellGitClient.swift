import Foundation

public struct ShellGitClient: GitClient {
    public let gitPath: String
    public let runner: any CommandRunning
    public let baseEnvironment: [String: String]

    public init(gitPath: String, runner: any CommandRunning, baseEnvironment: [String: String] = [:]) {
        self.gitPath = gitPath
        self.runner = runner
        self.baseEnvironment = baseEnvironment
    }

    public func execute(_ arguments: [String], in directory: URL?, environment: [String: String]) throws -> CommandResult {
        var env = baseEnvironment
        for (key, value) in environment { env[key] = value }
        return try runner.run(gitPath, arguments, cwd: directory, extraEnvironment: env)
    }
}
