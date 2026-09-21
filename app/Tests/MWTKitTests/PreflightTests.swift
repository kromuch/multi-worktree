import Foundation
import Testing
@testable import MWTKit

@Suite struct PreflightTests {
    let feature = try! FeatureName.parse("NODE-1")

    @Test func cleanCloneOnDefaultBranch() throws {
        let f = try GitFixture()
        let p = try Preflight(git: f.git).run(repo: RepoEntry(path: f.repo.path, isMain: true), feature: feature)
        #expect(p.remote == "origin")
        #expect(p.hasRemote)
        #expect(p.defaultBranch == "main")
        #expect(p.currentBranch == "main")
        #expect(p.remoteDefaultExists)
        #expect(!p.localFeatureBranchExists)
        #expect(!p.remoteFeatureBranchExists)
        #expect(!p.offersCurrentBranchBase)
        #expect(p.notices.isEmpty)
        #expect(URL(fileURLWithPath: p.commonDir).resolvingSymlinksInPath().path == f.repo.appending(path: ".git").resolvingSymlinksInPath().path)
    }

    @Test func noticesForDirtyTreeAheadDefaultAndExistingBranches() throws {
        let f = try GitFixture()
        try f.commit(file: "local.txt", content: "x\n", message: "ahead")
        try "dirty".write(to: f.repo.appending(path: "README.md"), atomically: true, encoding: .utf8)
        try f.git.run(["branch", "NODE-1"], in: f.repo)
        let p = try Preflight(git: f.git).run(repo: RepoEntry(path: f.repo.path, isMain: true), feature: feature)
        #expect(p.notices.contains { $0.contains("uncommitted") })
        #expect(p.notices.contains { $0.contains("ahead") })
        #expect(p.localFeatureBranchExists)
        #expect(p.notices.contains { $0.contains("reused") })
    }

    @Test func detectsRemoteFeatureBranchAndOffersCurrentBranch() throws {
        let f = try GitFixture()
        try f.git.run(["push", "--quiet", "origin", "main:NODE-1"], in: f.repo)
        try f.git.run(["checkout", "--quiet", "-b", "wip"], in: f.repo)
        let p = try Preflight(git: f.git).run(repo: RepoEntry(path: f.repo.path, isMain: true), feature: feature)
        #expect(p.remoteFeatureBranchExists)
        #expect(!p.localFeatureBranchExists)
        #expect(p.currentBranch == "wip")
        #expect(p.offersCurrentBranchBase)
    }

    @Test func recomputesMissingRemoteHead() throws {
        let f = try GitFixture()
        try f.git.run(["remote", "set-head", "origin", "--delete"], in: f.repo)
        let p = try Preflight(git: f.git).run(repo: RepoEntry(path: f.repo.path, isMain: true), feature: feature)
        #expect(p.defaultBranch == "main")
    }

    @Test func repoWithoutRemoteFallsBackToLocalDefault() throws {
        let root = try TempDir.make()
        let git = try GitFixture.makeClient()
        let repo = root.appending(path: "lonely")
        try git.run(["init", "--quiet", "--initial-branch=main", repo.path])
        try "x\n".write(to: repo.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try git.run(["add", "a.txt"], in: repo)
        try git.run(["commit", "--quiet", "-m", "init"], in: repo)
        let p = try Preflight(git: git).run(repo: RepoEntry(path: repo.path, isMain: true), feature: feature)
        #expect(!p.hasRemote)
        #expect(p.remote == "origin")
        #expect(p.defaultBranch == "main")
        #expect(!p.remoteDefaultExists)
        #expect(p.notices.contains { $0.contains("no remote") })
    }

    @Test func errorsForNonRepoSubdirectoryAndBadBranchName() throws {
        let f = try GitFixture()
        let plain = try TempDir.make()
        #expect(throws: PreflightError.notARepository(plain.path)) {
            try Preflight(git: f.git).run(repo: RepoEntry(path: plain.path, isMain: true), feature: feature)
        }
        let sub = f.repo.appending(path: "sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        #expect(throws: PreflightError.self) {
            try Preflight(git: f.git).run(repo: RepoEntry(path: sub.path, isMain: true), feature: feature)
        }
        #expect(throws: PreflightError.invalidBranchName("x.lock")) {
            try Preflight(git: f.git).run(repo: RepoEntry(path: f.repo.path, isMain: true), feature: try FeatureName.parse("x.lock"))
        }
    }

    @Test func runAllKeysResultsByPath() throws {
        let f = try GitFixture()
        let plain = try TempDir.make()
        let group = RepoGroup(name: "g", repos: [RepoEntry(path: f.repo.path, isMain: true), RepoEntry(path: plain.path, isMain: false)])
        let results = Preflight(git: f.git).runAll(group: group, feature: feature)
        #expect(results.count == 2)
        #expect((try? results[f.repo.path]?.get()) != nil)
        #expect(results[plain.path] == .failure(.notARepository(plain.path)))
    }

    @Test func runAllRunsConcurrentlyAndMatchesPerRepoRun() throws {
        let main = try GitFixture(name: "main")
        let sib1 = try GitFixture(name: "sib1")
        let sib2 = try GitFixture(name: "sib2")
        let plain = try TempDir.make()
        let group = RepoGroup(name: "g", repos: [
            RepoEntry(path: main.repo.path, isMain: true),
            RepoEntry(path: sib1.repo.path, isMain: false),
            RepoEntry(path: sib2.repo.path, isMain: false),
            RepoEntry(path: plain.path, isMain: false),
        ])
        let pf = Preflight(git: main.git)
        let results = pf.runAll(group: group, feature: feature)
        #expect(results.count == 4)
        for repo in group.repos where repo.path != plain.path {
            let entry = try #require(results[repo.path])
            let direct = try pf.run(repo: repo, feature: feature)
            #expect(try entry.get() == direct)
        }
        #expect(results[plain.path] == .failure(.notARepository(plain.path)))
    }
}
