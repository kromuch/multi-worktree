import Foundation
import Testing
@testable import MWTKit

@Suite struct GitClientTests {
    @Test func resolvesTopLevelAndCommonDir() throws {
        let f = try GitFixture()
        let sub = f.repo.appending(path: "sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        #expect(try f.git.topLevel(of: sub).resolvingSymlinksInPath().path == f.repo.resolvingSymlinksInPath().path)
        #expect(try f.git.commonDir(of: sub).resolvingSymlinksInPath().path == f.repo.appending(path: ".git").resolvingSymlinksInPath().path)
    }

    @Test func runThrowsGitErrorWithStderr() throws {
        let f = try GitFixture()
        #expect(throws: GitError.self) { try f.git.run(["rev-parse", "--verify", "definitely-missing"], in: f.repo) }
        #expect(!f.git.succeeds(["rev-parse", "--verify", "definitely-missing"], in: f.repo))
    }

    @Test func currentBranchAndDetachedHead() throws {
        let f = try GitFixture()
        #expect(f.git.currentBranch(in: f.repo) == "main")
        try f.git.run(["checkout", "--quiet", "--detach"], in: f.repo)
        #expect(f.git.currentBranch(in: f.repo) == nil)
    }

    @Test func remotesDefaultBranchAndRefs() throws {
        let f = try GitFixture()
        #expect(try f.git.remotes(in: f.repo) == ["origin"])
        #expect(f.git.configuredRemote(forBranch: "main", in: f.repo) == "origin")
        #expect(f.git.remoteHead(remote: "origin", in: f.repo) == "main")
        #expect(f.git.commitExists("origin/main", in: f.repo))
        #expect(!f.git.commitExists("origin/nope", in: f.repo))
        #expect(f.git.localBranchExists("main", in: f.repo))
        #expect(!f.git.localBranchExists("nope", in: f.repo))
        #expect(f.git.upstream(of: "main", in: f.repo) == "origin/main")
        #expect(f.git.upstream(of: "nope", in: f.repo) == nil)
    }

    @Test func remoteHeadCanBeRecomputed() throws {
        let f = try GitFixture()
        try f.git.run(["remote", "set-head", "origin", "--delete"], in: f.repo)
        #expect(f.git.remoteHead(remote: "origin", in: f.repo) == nil)
        #expect(f.git.setRemoteHeadAuto(remote: "origin", in: f.repo))
        #expect(f.git.remoteHead(remote: "origin", in: f.repo) == "main")
    }

    @Test func fetchAndRevListCount() throws {
        let f = try GitFixture()
        #expect(f.git.fetch(remote: "origin", in: f.repo))
        #expect(f.git.revListCount("origin/main..main", in: f.repo) == 0)
        try f.commit(file: "a.txt", content: "a\n", message: "local")
        #expect(f.git.revListCount("origin/main..main", in: f.repo) == 1)
        #expect(f.git.revListCount("origin/nope..main", in: f.repo) == nil)
    }

    @Test func branchNameValidationUsesGit() throws {
        let f = try GitFixture()
        #expect(f.git.isValidBranchName("feature/NODE-1"))
        #expect(!f.git.isValidBranchName("bad..name"))
        #expect(!f.git.isValidBranchName("name.lock"))
    }

    @Test func worktreeLifecycleWithNewBranch() throws {
        let f = try GitFixture()
        let wt = f.root.appending(path: "trees/feat/repo")
        try f.git.worktreeAdd(.createNew(branch: "feat", base: "origin/main"), at: wt, in: f.repo)
        let list = try f.git.worktrees(in: f.repo)
        let entry = try #require(list.first { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path == wt.resolvingSymlinksInPath().path })
        #expect(entry.branch == "feat")
        #expect(!entry.isDetached)
        #expect(f.git.upstream(of: "feat", in: f.repo) == nil)
        #expect(try f.git.statusLines(in: wt).isEmpty)

        try "dirty\n".write(to: wt.appending(path: "dirty.txt"), atomically: true, encoding: .utf8)
        #expect(try f.git.statusLines(in: wt) == ["?? dirty.txt"])
        #expect(throws: GitError.self) { try f.git.worktreeRemove(wt, force: false, in: f.repo) }
        try f.git.worktreeRemove(wt, force: true, in: f.repo)
        f.git.worktreePrune(in: f.repo)
        #expect(!FileManager.default.fileExists(atPath: wt.path))
        #expect(f.git.localBranchExists("feat", in: f.repo))
        try f.git.deleteBranch("feat", in: f.repo)
        #expect(!f.git.localBranchExists("feat", in: f.repo))
    }

    @Test func worktreeFromExistingLocalBranchAndFromRemoteBranch() throws {
        let f = try GitFixture()
        try f.git.run(["branch", "local-feat"], in: f.repo)
        let wt1 = f.root.appending(path: "trees/local-feat/repo")
        try f.git.worktreeAdd(.reuseLocal("local-feat"), at: wt1, in: f.repo)
        #expect(try f.git.worktrees(in: f.repo).contains { $0.branch == "local-feat" })

        try f.git.run(["branch", "remote-feat"], in: f.repo)
        try f.git.run(["push", "--quiet", "origin", "remote-feat"], in: f.repo)
        try f.git.run(["branch", "-D", "remote-feat"], in: f.repo)
        let wt2 = f.root.appending(path: "trees/remote-feat/repo")
        try f.git.worktreeAdd(.trackRemote(remote: "origin", branch: "remote-feat"), at: wt2, in: f.repo)
        #expect(f.git.upstream(of: "remote-feat", in: f.repo) == "origin/remote-feat")
    }

    @Test func worktreeListMarksPrunableEntries() throws {
        let f = try GitFixture()
        let wt = f.root.appending(path: "trees/gone/repo")
        try f.git.worktreeAdd(.createNew(branch: "gone", base: "origin/main"), at: wt, in: f.repo)
        try FileManager.default.removeItem(at: wt)
        let entry = try #require(try f.git.worktrees(in: f.repo).first { $0.branch == "gone" })
        #expect(entry.isPrunable)
        f.git.worktreePrune(in: f.repo)
        #expect(try f.git.worktrees(in: f.repo).allSatisfy { $0.branch != "gone" })
    }

    @Test func listsIgnoredFiles() throws {
        let f = try GitFixture()
        try f.commit(file: ".gitignore", content: "*.log\nbuild/\n", message: "ignore")
        try "x".write(to: f.repo.appending(path: "a.log"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: f.repo.appending(path: "build"), withIntermediateDirectories: true)
        try "x".write(to: f.repo.appending(path: "build/out.o"), atomically: true, encoding: .utf8)
        try "x".write(to: f.repo.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        #expect(try f.git.ignoredFiles(in: f.repo).sorted() == ["a.log", "build/out.o"])
    }
}
