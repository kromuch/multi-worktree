import Foundation
import Testing
@testable import MWTKit

@Suite struct SpinUpTests {
    @Test func happyPathWiresMainWorktreeAndOpensClaude() throws {
        let h = try SpinUpHarness()
        try """
        {"projects":{"\(h.main.repo.path)":{"mcpServers":{"jira":{}}}}}
        """.write(to: h.home.appending(path: ".claude.json"), atomically: true, encoding: .utf8)
        let claudeJSONBefore = try Data(contentsOf: h.home.appending(path: ".claude.json"))

        let (manifest, report) = try h.spinUp()

        #expect(report.hardError == nil)
        #expect(report.outcomes.map(\.label) == [.created, .created])
        #expect(report.openedClaude)
        #expect(h.opener.opened == [DeepLink.newSession(folder: h.mainWorktree)])
        #expect(report.notes.contains { $0.contains("MCP") })

        #expect(FileManager.default.fileExists(atPath: h.mainWorktree.appending(path: "README.md").path))
        #expect(FileManager.default.fileExists(atPath: h.siblingWorktree.appending(path: "README.md").path))
        #expect(h.git.currentBranch(in: h.mainWorktree) == "NODE-1")
        #expect(h.git.currentBranch(in: h.siblingWorktree) == "NODE-1")
        #expect(h.git.upstream(of: "NODE-1", in: h.main.repo) == nil)

        let permissions = try h.settings()
        #expect(permissions["additionalDirectories"] as? [String] == [h.siblingWorktree.path])
        #expect(permissions["deny"] as? [String] == DenyRules.rules(forOriginal: h.sibling.repo.path))

        let exclude = try String(contentsOf: h.main.repo.appending(path: ".git/info/exclude"), encoding: .utf8)
        #expect(exclude.contains(".claude/settings.local.json\n"))
        #expect(exclude.contains("CLAUDE.local.md\n"))
        let rules = try String(contentsOf: h.mainWorktree.appending(path: "CLAUDE.local.md"), encoding: .utf8)
        #expect(rules.contains("feature `NODE-1`"))
        #expect(rules.contains(h.siblingWorktree.path))
        #expect(try h.git.statusLines(in: h.mainWorktree).isEmpty)

        #expect(manifest.group == "set")
        #expect(manifest.mainWorktree == h.mainWorktree.path)
        #expect(manifest.denyEntries == DenyRules.rules(forOriginal: h.sibling.repo.path))
        let mainEntry = try #require(manifest.repos.first { $0.isMain })
        #expect(mainEntry.remote == "origin")
        #expect(mainEntry.defaultBranch == "main")
        #expect(mainEntry.baseRef == "origin/main")
        #expect(mainEntry.branchCreated)
        #expect(mainEntry.status == .created)
        #expect(try h.store.loadManifest(segment: "NODE-1") == manifest)

        #expect(!FileManager.default.fileExists(atPath: h.home.appending(path: ".claude/projects").path))
        #expect(try Data(contentsOf: h.home.appending(path: ".claude.json")) == claudeJSONBefore)
    }

    @Test func rerunReusesWorktreesWithoutDuplicatingSettings() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp()
        let (_, second) = try h.spinUp()
        #expect(second.outcomes.map(\.label) == [.reused, .reused])
        let permissions = try h.settings()
        #expect(permissions["additionalDirectories"] as? [String] == [h.siblingWorktree.path])
        #expect((permissions["deny"] as? [String])?.count == 2)
        #expect(h.opener.opened.count == 2)
    }

    @Test func failedSiblingIsReportedAndClaudeIsNotOpened() throws {
        let h = try SpinUpHarness()
        let plain = try TempDir.make()
        let group = RepoGroup(name: "set", repos: [RepoEntry(path: h.main.repo.path, isMain: true), RepoEntry(path: plain.path, isMain: false)])
        let (manifest, report) = try h.spinUp(group: group)
        #expect(report.hardError == nil)
        #expect(report.outcomes.map(\.label) == [.created, .failed])
        #expect(!report.openedClaude)
        #expect(h.opener.opened.isEmpty)
        #expect(report.notes.contains { $0.contains("not opened") })
        #expect(manifest.repos.first { !$0.isMain }?.status == .failed)
        let permissions = try h.settings()
        #expect(permissions["additionalDirectories"] as? [String] == [])
        #expect(permissions["deny"] as? [String] == DenyRules.rules(forOriginal: plain.path))
        let rules = try String(contentsOf: h.mainWorktree.appending(path: "CLAUDE.local.md"), encoding: .utf8)
        #expect(rules.contains("unavailable"))
        #expect(rules.contains("`\(plain.lastPathComponent)`"))
    }

    @Test func siblingDroppedFromGroupLosesWiringButKeepsManifestAndWorktree() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp()
        #expect(FileManager.default.fileExists(atPath: h.siblingWorktree.path))

        let mainOnly = RepoGroup(name: "set", repos: [RepoEntry(path: h.main.repo.path, isMain: true)])
        let (manifest, report) = try h.spinUp(group: mainOnly)
        #expect(report.hardError == nil)

        let permissions = try h.settings()
        #expect(permissions["additionalDirectories"] as? [String] == [])
        let deny = permissions["deny"] as? [String] ?? []
        #expect(!deny.contains { $0.contains(h.sibling.repo.path) })

        let siblingEntry = try #require(manifest.repos.first { !$0.isMain })
        #expect(siblingEntry.path == h.sibling.repo.path)
        #expect(siblingEntry.worktree == h.siblingWorktree.path)
        #expect(FileManager.default.fileExists(atPath: h.siblingWorktree.path))

        let saved = try #require(try h.store.loadManifest(segment: "NODE-1"))
        #expect(saved.repos.contains { $0.path == h.sibling.repo.path })
    }

    @Test func failedMainIsAHardErrorWithoutWiring() throws {
        let h = try SpinUpHarness()
        let plain = try TempDir.make()
        let group = RepoGroup(name: "set", repos: [RepoEntry(path: plain.path, isMain: true), RepoEntry(path: h.sibling.repo.path, isMain: false)])
        let (manifest, report) = try h.spinUp(group: group)
        #expect(report.hardError != nil)
        #expect(h.opener.opened.isEmpty)
        #expect(manifest.repos.first { $0.isMain }?.status == .failed)
        #expect(manifest.repos.first { !$0.isMain }?.status == .created)
        #expect(!FileManager.default.fileExists(atPath: h.store.paths.worktreeURL(segment: "NODE-1", basename: plain.lastPathComponent).appending(path: ".claude").path))
    }

    @Test func occupiedTargetPathFailsOnlyThatRepo() throws {
        let h = try SpinUpHarness()
        try FileManager.default.createDirectory(at: h.siblingWorktree, withIntermediateDirectories: true)
        try "junk".write(to: h.siblingWorktree.appending(path: "junk.txt"), atomically: true, encoding: .utf8)
        let (_, report) = try h.spinUp()
        #expect(report.outcomes.map(\.label) == [.created, .failed])
        #expect(report.outcomes[1].reasons.joined().contains(h.siblingWorktree.path))
    }

    @Test func featureNameOwnedByAnotherGroupIsRejected() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp()
        let other = RepoGroup(name: "other-set", repos: [RepoEntry(path: h.main.repo.path, isMain: true)])
        #expect(throws: SpinUpError.featureUsedByOtherGroup(feature: "NODE-1", group: "set")) {
            _ = try h.spinUp(group: other)
        }
    }

    @Test func copiesWorktreeIncludeFiles() throws {
        let h = try SpinUpHarness()
        try h.main.commit(file: ".gitignore", content: ".env\n", message: "ignore")
        try h.main.commit(file: ".worktreeinclude", content: ".env\n", message: "include")
        try h.git.run(["push", "--quiet", "origin", "main"], in: h.main.repo)
        try "SECRET=1\n".write(to: h.main.repo.appending(path: ".env"), atomically: true, encoding: .utf8)
        let (_, report) = try h.spinUp()
        #expect(try String(contentsOf: h.mainWorktree.appending(path: ".env"), encoding: .utf8) == "SECRET=1\n")
        #expect(report.outcomes[0].reasons.contains { $0.contains("copied 1") })
        #expect(try h.git.statusLines(in: h.mainWorktree).isEmpty)
    }

    @Test func currentBranchChoiceUsesLocalTip() throws {
        let h = try SpinUpHarness()
        try h.git.run(["checkout", "--quiet", "-b", "wip"], in: h.main.repo)
        let tip = try h.main.commit(file: "wip.txt", content: "w\n", message: "wip work")
        let (manifest, _) = try h.spinUp(choices: [h.main.repo.path: .currentBranch])
        #expect(manifest.repos.first { $0.isMain }?.baseRef == "wip")
        #expect(try h.git.run(["rev-parse", "HEAD"], in: h.mainWorktree) == tip)
    }
}
