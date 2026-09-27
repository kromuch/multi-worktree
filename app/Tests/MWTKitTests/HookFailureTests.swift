import Foundation
import Testing
@testable import MWTKit

@Suite struct HookFailureTests {
    func installHook(_ body: String, in repo: URL) throws {
        let hook = repo.appending(path: ".git/hooks/post-checkout")
        try "#!/bin/sh\n\(body)\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    }

    @Test func failingPostCheckoutHookIsAWarningNotAFailure() throws {
        let h = try SpinUpHarness()
        try installHook("echo 'hook says no' >&2\nexit 1", in: h.main.repo)

        let (manifest, report) = try h.spinUp()

        #expect(report.hardError == nil)
        #expect(report.outcomes.map(\.label) == [.warned, .created])
        let reasons = report.outcomes[0].reasons
        #expect(reasons.contains("new branch ABC-1 from origin/main"))
        #expect(reasons.contains { $0.hasPrefix("post-checkout hook failed (exit 1): hook says no. ") })
        let mainEntry = try #require(manifest.repos.first { $0.isMain })
        #expect(mainEntry.status == .created)
        #expect(mainEntry.branchCreated)
        #expect(mainEntry.baseRef == "origin/main")
        #expect(h.git.currentBranch(in: h.mainWorktree) == "ABC-1")
        #expect(FileManager.default.fileExists(atPath: h.mainWorktree.appending(path: "CLAUDE.local.md").path))
        #expect(try h.settings()["additionalDirectories"] as? [String] == [h.siblingWorktree.path])
        #expect(report.openedClaude)
    }

    @Test func hookFailureReasonDropsGitProgressLinesAndKeepsTheLastThree() {
        let error = GitError(arguments: ["worktree", "add"], status: 127, stderr: """
        Preparing worktree (new branch 'ABC-1')
        HEAD is now at 1234567 init
        one
        two
        three
        .husky/post-checkout: line 3: node: command not found
        """)
        #expect(HookFailure.reason(for: error)
            == "post-checkout hook failed (exit 127): two three .husky/post-checkout: line 3: node: command not found. "
            + "MultiWorktree runs git with your login-shell PATH (or the fallback PATH); tools the hook needs may be missing.")
    }

    @Test func worktreeAddFailureThatLeavesNoWorktreeIsStillAFailure() throws {
        let h = try SpinUpHarness()
        try FileManager.default.createDirectory(at: h.siblingWorktree.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "occupied".write(to: h.siblingWorktree, atomically: true, encoding: .utf8)

        let (manifest, report) = try h.spinUp()

        #expect(report.outcomes.map(\.label) == [.created, .failed])
        #expect(report.outcomes[1].reasons.joined().contains("worktree add"))
        #expect(manifest.repos.first { !$0.isMain }?.status == .failed)
    }
}
