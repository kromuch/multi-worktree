import Foundation
import Testing
@testable import MWTKit

@Suite struct ToolEnvironmentTests {
    @Test func fixedEnvironmentUsesTheHomebrewFirstPath() {
        #expect(ToolEnvironment.fixed.path == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(ToolEnvironment.fixed.source == .fixed)
        #expect(ToolEnvironment.fixed.entries == ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    }

    @Test func childEnvironmentUsesThisInstancesPath() {
        let env = ToolEnvironment(path: "/a/bin:/b/bin", source: .loginShell).childEnvironment(base: ["PATH": "/nope", "X": "1"])
        #expect(env["PATH"] == "/a/bin:/b/bin")
        #expect(env["X"] == "1")
    }

    @Test func findExecutableReturnsTheFirstMatchInPathOrder() {
        let env = ToolEnvironment(path: "/one:/two/:/three", source: .fixed)
        let found = env.findExecutable("git") { $0 == "/two/git" || $0 == "/three/git" }
        #expect(found == "/two/git")
        #expect(env.findExecutable("git") { _ in false } == nil)
    }

    @Test func mergeKeepsPrimaryOrderAndAppendsMissingFallbackEntries() {
        let merged = ToolPath.merge(primary: ["/nvm/bin", "/usr/bin/", "/opt/homebrew/bin"],
                                    fallback: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
        #expect(merged == ["/nvm/bin", "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin", "/bin"])
    }

    @Test func mergeDropsEmptyEntriesAndKeepsRoot() {
        #expect(ToolPath.merge(primary: ["", "/", "/a//"], fallback: []) == ["/", "/a"])
    }
}
