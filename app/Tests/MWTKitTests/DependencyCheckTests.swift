import Foundation
import Testing
@testable import MWTKit

final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let responses: [String: Result<CommandResult, CommandTimeout>]
    private let lock = NSLock()
    private var log: [String] = []

    init(_ responses: [String: Result<CommandResult, CommandTimeout>]) {
        self.responses = responses
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func run(_ executable: String, _ arguments: [String], cwd: URL?, extraEnvironment: [String: String],
             timeout: Duration?) throws -> CommandResult {
        lock.lock()
        log.append(([executable] + arguments).joined(separator: " "))
        lock.unlock()
        switch responses[executable] {
        case .success(let result)?: return result
        case .failure(let error)?: throw error
        case nil: return CommandResult(status: 127, stdout: "", stderr: "not faked: \(executable)")
        }
    }
}

@Suite struct GitVersionTests {
    @Test func parsesPlainAppleAndTwoPartVersions() {
        #expect(GitVersion.parse("git version 2.54.0\n") == GitVersion(major: 2, minor: 54, patch: 0))
        #expect(GitVersion.parse("git version 2.39.5 (Apple Git-154)\n") == GitVersion(major: 2, minor: 39, patch: 5))
        #expect(GitVersion.parse("git version 2.31") == GitVersion(major: 2, minor: 31, patch: 0))
        #expect(GitVersion.parse("git version 2.45.0-rc1") == GitVersion(major: 2, minor: 45, patch: 0))
    }

    @Test func rejectsGarbage() {
        #expect(GitVersion.parse("") == nil)
        #expect(GitVersion.parse("hello") == nil)
        #expect(GitVersion.parse("git version two") == nil)
    }

    @Test func comparesAgainstTheMinimum() {
        #expect(GitVersion(major: 2, minor: 30, patch: 9) < GitVersion.minimum)
        #expect(!(GitVersion(major: 2, minor: 31, patch: 0) < GitVersion.minimum))
        #expect(GitVersion(major: 2, minor: 54, patch: 0).description == "2.54.0")
    }
}

@Suite struct DependencyCheckTests {
    let appleOnly = ToolEnvironment(path: "/usr/bin:/bin", source: .loginShell)
    let withHomebrew = ToolEnvironment(path: "/opt/homebrew/bin:/usr/bin:/bin", source: .fallback(reason: "no PATH in shell output"))

    func check(executables: Set<String>, claude: Bool = true) -> DependencyCheck {
        DependencyCheck(isExecutable: { executables.contains($0) },
                        canonicalPath: { $0 == "/opt/homebrew/bin/git" ? "/opt/homebrew/Cellar/git/2.54.0/bin/git" : $0 },
                        claudeInstalled: { claude })
    }

    func version(_ text: String) -> Result<CommandResult, CommandTimeout> {
        .success(CommandResult(status: 0, stdout: text, stderr: ""))
    }

    @Test func appleShimWithoutCommandLineToolsIsNeverExecuted() {
        let runner = FakeRunner(["/usr/bin/xcode-select": .success(CommandResult(status: 2, stdout: "", stderr: "xcode-select: error"))])
        let report = check(executables: ["/usr/bin/git"]).run(environment: appleOnly, runner: runner)
        #expect(report.git == .needsCommandLineTools)
        #expect(runner.calls == ["/usr/bin/xcode-select -p"])
    }

    @Test func appleGitWithCommandLineToolsIsReady() {
        let runner = FakeRunner([
            "/usr/bin/xcode-select": .success(CommandResult(status: 0, stdout: "/Library/Developer/CommandLineTools\n", stderr: "")),
            "/usr/bin/git": version("git version 2.39.5 (Apple Git-154)\n"),
        ])
        let report = check(executables: ["/usr/bin/git"]).run(environment: appleOnly, runner: runner)
        #expect(report.git == .ready(path: "/usr/bin/git", version: GitVersion(major: 2, minor: 39, patch: 5)))
        #expect(runner.calls == ["/usr/bin/xcode-select -p", "/usr/bin/git --version"])
    }

    @Test func homebrewGitSkipsTheCommandLineToolsProbe() {
        let runner = FakeRunner(["/opt/homebrew/bin/git": version("git version 2.54.0\n")])
        let report = check(executables: ["/opt/homebrew/bin/git", "/usr/bin/git"]).run(environment: withHomebrew, runner: runner)
        #expect(report.git == .ready(path: "/opt/homebrew/bin/git", version: GitVersion(major: 2, minor: 54, patch: 0)))
        #expect(runner.calls == ["/opt/homebrew/bin/git --version"])
        #expect(report.environment == withHomebrew)
    }

    @Test func oldGitIsTooOld() {
        let runner = FakeRunner(["/opt/homebrew/bin/git": version("git version 2.24.3\n")])
        let report = check(executables: ["/opt/homebrew/bin/git"]).run(environment: withHomebrew, runner: runner)
        #expect(report.git == .tooOld(path: "/opt/homebrew/bin/git", version: GitVersion(major: 2, minor: 24, patch: 3)))
    }

    @Test func failingGitIsBrokenWithTheFirstStderrLine() {
        let runner = FakeRunner(["/opt/homebrew/bin/git": .success(CommandResult(status: 1, stdout: "", stderr: "\ndyld: Library not loaded\nreason\n"))])
        let report = check(executables: ["/opt/homebrew/bin/git"]).run(environment: withHomebrew, runner: runner)
        #expect(report.git == .broken(path: "/opt/homebrew/bin/git", message: "dyld: Library not loaded"))
    }

    @Test func hangingGitIsBroken() {
        let runner = FakeRunner(["/opt/homebrew/bin/git": .failure(CommandTimeout(executable: "/opt/homebrew/bin/git", seconds: 10))])
        let report = check(executables: ["/opt/homebrew/bin/git"]).run(environment: withHomebrew, runner: runner)
        #expect(report.git == .broken(path: "/opt/homebrew/bin/git", message: "/opt/homebrew/bin/git did not finish in 10 s"))
    }

    @Test func unparsableVersionIsBroken() {
        let runner = FakeRunner(["/opt/homebrew/bin/git": version("hello\n")])
        let report = check(executables: ["/opt/homebrew/bin/git"]).run(environment: withHomebrew, runner: runner)
        #expect(report.git == .broken(path: "/opt/homebrew/bin/git", message: "unrecognized version output: hello"))
    }

    @Test func noGitAnywhereIsMissing() {
        let runner = FakeRunner([:])
        let report = check(executables: []).run(environment: appleOnly, runner: runner)
        #expect(report.git == .missing)
        #expect(runner.calls.isEmpty)
    }

    @Test func claudeFlagIsReported() {
        let runner = FakeRunner(["/opt/homebrew/bin/git": version("git version 2.54.0\n")])
        #expect(check(executables: ["/opt/homebrew/bin/git"], claude: false).run(environment: withHomebrew, runner: runner).claudeInstalled == false)
        #expect(check(executables: ["/opt/homebrew/bin/git"], claude: true).run(environment: withHomebrew, runner: runner).claudeInstalled)
    }

    @Test func realCheckOnThisMachineFindsAWorkingGit() {
        let report = DependencyCheck(claudeInstalled: { true }).run(environment: .fixed, runner: ProcessRunner())
        #expect(report.git.isReady)
    }
}
