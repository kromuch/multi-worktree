import Foundation
import Testing
@testable import MWTKit

@Suite struct CommandRunnerTests {
    let runner = ProcessRunner()

    @Test func capturesStdoutAndStatus() throws {
        let r = try runner.run("/bin/echo", ["hello"], cwd: nil, extraEnvironment: [:])
        #expect(r.status == 0)
        #expect(r.succeeded)
        #expect(r.stdout == "hello\n")
        #expect(r.stderr == "")
    }

    @Test func capturesStderrAndNonZeroStatus() throws {
        let r = try runner.run("/bin/sh", ["-c", "echo oops 1>&2; exit 3"], cwd: nil, extraEnvironment: [:])
        #expect(r.status == 3)
        #expect(!r.succeeded)
        #expect(r.stderr == "oops\n")
    }

    @Test func childGetsFixedPathAndExtraEnvironment() throws {
        let r = try runner.run("/bin/sh", ["-c", "echo $PATH; echo $MWT_PROBE"], cwd: nil, extraEnvironment: ["MWT_PROBE": "42"])
        #expect(r.stdout == "\(ToolEnvironment.path)\n42\n")
    }

    @Test func honoursWorkingDirectory() throws {
        let dir = try TempDir.make()
        let r = try runner.run("/bin/pwd", [], cwd: dir, extraEnvironment: [:])
        let observed = URL(fileURLWithPath: r.stdout.trimmingCharacters(in: .newlines)).resolvingSymlinksInPath().path
        #expect(observed == dir.resolvingSymlinksInPath().path)
    }

    @Test func handlesLargeOutputWithoutDeadlock() throws {
        let r = try runner.run("/bin/sh", ["-c", "yes abcdefghij | head -n 200000; yes err | head -n 100000 1>&2"], cwd: nil, extraEnvironment: [:])
        #expect(r.stdout.count == 200_000 * 11)
        #expect(r.stderr.count == 100_000 * 4)
    }

    @Test func childEnvironmentOverridesPathAndKeepsHomeAndSSHAgent() {
        let env = ToolEnvironment.childEnvironment(base: ["PATH": "/nope", "SSH_AUTH_SOCK": "/tmp/agent.sock", "HOME": "/Users/x"])
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(env["SSH_AUTH_SOCK"] == "/tmp/agent.sock")
        #expect(env["HOME"] == "/Users/x")
        #expect(ToolEnvironment.childEnvironment(base: [:])["HOME"] != nil)
    }

    @Test func resolvesAnExistingGitBinary() throws {
        let git = try #require(ToolEnvironment.resolveGit())
        #expect(git.hasSuffix("/git"))
        #expect(FileManager.default.isExecutableFile(atPath: git))
    }
}
