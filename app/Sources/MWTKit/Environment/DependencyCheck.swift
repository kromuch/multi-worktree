import Foundation

public enum GitStatus: Equatable, Sendable {
    case ready(path: String, version: GitVersion)
    case needsCommandLineTools
    case missing
    case tooOld(path: String, version: GitVersion)
    case broken(path: String, message: String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public struct DependencyReport: Equatable, Sendable {
    public var environment: ToolEnvironment
    public var git: GitStatus
    public var claudeInstalled: Bool

    public init(environment: ToolEnvironment, git: GitStatus, claudeInstalled: Bool) {
        self.environment = environment
        self.git = git
        self.claudeInstalled = claudeInstalled
    }
}

public struct DependencyCheck: Sendable {
    public static let appleGitShim = "/usr/bin/git"
    public static let xcodeSelect = "/usr/bin/xcode-select"
    public static let probeTimeout: Duration = .seconds(10)

    public var isExecutable: @Sendable (String) -> Bool
    public var canonicalPath: @Sendable (String) -> String
    public var claudeInstalled: @Sendable () -> Bool

    public init(isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                canonicalPath: @escaping @Sendable (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                claudeInstalled: @escaping @Sendable () -> Bool) {
        self.isExecutable = isExecutable
        self.canonicalPath = canonicalPath
        self.claudeInstalled = claudeInstalled
    }

    public func run(environment: ToolEnvironment, runner: any CommandRunning) -> DependencyReport {
        DependencyReport(environment: environment,
                         git: gitStatus(environment: environment, runner: runner),
                         claudeInstalled: claudeInstalled())
    }

    func gitStatus(environment: ToolEnvironment, runner: any CommandRunning) -> GitStatus {
        guard let path = environment.findExecutable("git", isExecutable: isExecutable) else { return .missing }
        if canonicalPath(path) == Self.appleGitShim {
            let select = try? runner.run(Self.xcodeSelect, ["-p"], cwd: nil, extraEnvironment: [:], timeout: Self.probeTimeout)
            guard select?.succeeded == true else { return .needsCommandLineTools }
        }
        let result: CommandResult
        do {
            result = try runner.run(path, ["--version"], cwd: nil, extraEnvironment: [:], timeout: Self.probeTimeout)
        } catch {
            return .broken(path: path, message: String(describing: error))
        }
        guard result.succeeded else {
            return .broken(path: path, message: Self.firstLine(result.stderr) ?? "exited with status \(result.status)")
        }
        guard let version = GitVersion.parse(result.stdout) else {
            return .broken(path: path, message: "unrecognized version output: \(Self.firstLine(result.stdout) ?? "")")
        }
        return version < GitVersion.minimum ? .tooOld(path: path, version: version) : .ready(path: path, version: version)
    }

    static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}
