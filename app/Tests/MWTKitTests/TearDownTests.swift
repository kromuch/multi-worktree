import Foundation
import Testing
@testable import MWTKit

@Suite struct TearDownTests {
    func tearDown(_ h: SpinUpHarness, confirmed: Set<String> = []) throws -> (manifest: FeatureManifest?, report: RunReport) {
        try TearDown(git: h.git, store: h.store).run(TearDownRequest(segment: "NODE-1", discardConfirmedRepoPaths: confirmed))
    }

    @Test func cleanFeatureIsFullyRemovedAndUntouchedBranchesDeleted() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp(openClaude: false)
        let (manifest, report) = try tearDown(h)
        #expect(manifest == nil)
        #expect(report.outcomes.map(\.label) == [.removed, .removed])
        #expect(report.outcomes.allSatisfy { $0.reasons.contains { $0.contains("branch deleted") } })
        #expect(!FileManager.default.fileExists(atPath: h.mainWorktree.path))
        #expect(!FileManager.default.fileExists(atPath: h.store.paths.treeDir(segment: "NODE-1").path))
        #expect(!h.git.localBranchExists("NODE-1", in: h.main.repo))
        #expect(!h.git.localBranchExists("NODE-1", in: h.sibling.repo))
        #expect(try h.store.loadManifest(segment: "NODE-1") == nil)
        #expect(try h.git.worktrees(in: h.main.repo).count == 1)
    }

    @Test func unpushedCommitsKeepTheBranchButRemoveTheWorktree() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp(openClaude: false)
        try h.main.commit(file: "work.txt", content: "w\n", message: "work", in: h.mainWorktree)
        let (manifest, report) = try tearDown(h)
        #expect(manifest == nil)
        #expect(!FileManager.default.fileExists(atPath: h.mainWorktree.path))
        #expect(h.git.localBranchExists("NODE-1", in: h.main.repo))
        #expect(report.outcomes[0].reasons.contains { $0.contains("unpushed") })
        #expect(!h.git.localBranchExists("NODE-1", in: h.sibling.repo))
    }

    @Test func fullyPushedBranchIsDeleted() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp(openClaude: false)
        try h.main.commit(file: "work.txt", content: "w\n", message: "work", in: h.mainWorktree)
        try h.git.run(["push", "--quiet", "-u", "origin", "NODE-1"], in: h.mainWorktree)
        let (_, report) = try tearDown(h)
        #expect(!h.git.localBranchExists("NODE-1", in: h.main.repo))
        #expect(report.outcomes[0].reasons.contains { $0.contains("fully pushed") })
    }

    @Test func dirtyWorktreeIsKeptUntilDiscardIsConfirmed() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp(openClaude: false)
        try "scratch".write(to: h.siblingWorktree.appending(path: "scratch.txt"), atomically: true, encoding: .utf8)

        let (kept, first) = try tearDown(h)
        #expect(first.outcomes.map(\.label) == [.removed, .kept])
        #expect(first.outcomes[1].reasons.contains { $0.contains("uncommitted") })
        #expect(kept?.repos.first { !$0.isMain }?.status == .created)
        #expect(kept?.repos.first { $0.isMain }?.status == .removed)
        #expect(FileManager.default.fileExists(atPath: h.siblingWorktree.path))

        let (gone, second) = try tearDown(h, confirmed: [h.sibling.repo.path])
        #expect(gone == nil)
        #expect(second.outcomes.map(\.label) == [.removed])
        #expect(second.outcomes[0].reasons.contains { $0.contains("discarded") })
        #expect(!FileManager.default.fileExists(atPath: h.siblingWorktree.path))
    }

    @Test func worktreeRemovedOutOfBandIsReconciled() throws {
        let h = try SpinUpHarness()
        _ = try h.spinUp(openClaude: false)
        try FileManager.default.removeItem(at: h.siblingWorktree)
        let (manifest, report) = try tearDown(h)
        #expect(manifest == nil)
        #expect(report.outcomes[1].label == .removed)
        #expect(report.outcomes[1].reasons.contains("already removed"))
        #expect(!h.git.localBranchExists("NODE-1", in: h.sibling.repo))
        #expect(try h.git.worktrees(in: h.sibling.repo).count == 1)
    }

    @Test func repoWithoutRemoteKeepsItsBranch() throws {
        let h = try SpinUpHarness()
        let lonely = h.root.appending(path: "lonely")
        try h.git.run(["init", "--quiet", "--initial-branch=main", lonely.path])
        try h.main.commit(file: "a.txt", content: "a\n", message: "init", in: lonely)
        let group = RepoGroup(name: "set", repos: [RepoEntry(path: h.main.repo.path, isMain: true), RepoEntry(path: lonely.path, isMain: false)])
        _ = try h.spinUp(group: group, openClaude: false)
        let (_, report) = try tearDown(h)
        #expect(report.outcomes[1].label == .removed)
        #expect(report.outcomes[1].reasons.contains { $0.contains("branch kept") })
        #expect(h.git.localBranchExists("NODE-1", in: lonely))
    }

    @Test func missingManifestThrows() throws {
        let h = try SpinUpHarness()
        #expect(throws: TearDownError.noManifest("NODE-1")) { try tearDown(h) }
    }
}
