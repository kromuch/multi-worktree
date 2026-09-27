import Foundation
import Testing
@testable import MWTKit

@Suite struct LoginShellPathTests {
    @Test func extractsPathBetweenMarkersIgnoringNoise() {
        let output = "Welcome back!\n__MWT_PATH__/nvm/bin:/opt/homebrew/bin__MWT_PATH__\nlogout\n"
        #expect(LoginShellPath.extract(from: output) == ["/nvm/bin", "/opt/homebrew/bin"])
    }

    @Test func dropsEmptyAndRelativeEntries() {
        #expect(LoginShellPath.extract(from: "__MWT_PATH__/a::bin:./x:/b/__MWT_PATH__") == ["/a", "/b/"])
    }

    @Test func missingMarkersOrEmptyValueYieldNil() {
        #expect(LoginShellPath.extract(from: "/usr/bin:/bin") == nil)
        #expect(LoginShellPath.extract(from: "__MWT_PATH__/usr/bin") == nil)
        #expect(LoginShellPath.extract(from: "__MWT_PATH____MWT_PATH__") == nil)
        #expect(LoginShellPath.extract(from: "__MWT_PATH__relative__MWT_PATH__") == nil)
    }

    @Test func userShellIsAnExecutablePath() {
        #expect(FileManager.default.isExecutableFile(atPath: LoginShellPath.userShell()))
    }

    @Test func resolvesPathSetByInteractiveZshStartupFiles() throws {
        let dir = try TempDir.make()
        try "echo 'hello from zshrc'\nexport PATH=/mwt/probe/bin:$PATH\n"
            .write(to: dir.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        let env = ToolEnvironment.resolveFromLoginShell(shell: "/bin/zsh", extraEnvironment: ["ZDOTDIR": dir.path])
        #expect(env.source == .loginShell)
        #expect(env.entries.first == "/mwt/probe/bin")
        #expect(env.entries.contains("/opt/homebrew/bin"))
        #expect(Set(env.entries).count == env.entries.count)
    }

    @Test func passesTheResolvingMarkerToStartupFiles() throws {
        let dir = try TempDir.make()
        try "export PATH=/resolving/$MWT_RESOLVING_PATH:$PATH\n"
            .write(to: dir.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        let env = ToolEnvironment.resolveFromLoginShell(shell: "/bin/zsh", extraEnvironment: ["ZDOTDIR": dir.path])
        #expect(env.entries.first == "/resolving/1")
    }

    @Test func slowStartupFilesFallBackWithinTheTimeout() throws {
        let dir = try TempDir.make()
        try "sleep 30\n".write(to: dir.appending(path: ".zshrc"), atomically: true, encoding: .utf8)
        let start = Date()
        let env = ToolEnvironment.resolveFromLoginShell(shell: "/bin/zsh", extraEnvironment: ["ZDOTDIR": dir.path],
                                                        timeout: .milliseconds(500))
        #expect(env == ToolEnvironment(path: ToolEnvironment.fixedPath, source: .fallback(reason: "shell did not finish in 0.5 s")))
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func failingShellWithoutOutputFallsBack() {
        let env = ToolEnvironment.resolveFromLoginShell(shell: "/usr/bin/false")
        #expect(env.source == .fallback(reason: "shell exited with status 1 and printed no PATH"))
        #expect(env.path == ToolEnvironment.fixedPath)
    }

    @Test func succeedingShellWithoutOutputFallsBack() {
        #expect(ToolEnvironment.resolveFromLoginShell(shell: "/usr/bin/true").source == .fallback(reason: "no PATH in shell output"))
    }

    @Test func missingShellFallsBack() {
        guard case .fallback(let reason) = ToolEnvironment.resolveFromLoginShell(shell: "/nonexistent/shell").source else {
            Issue.record("expected fallback")
            return
        }
        #expect(reason.hasPrefix("could not start /nonexistent/shell"))
    }
}
