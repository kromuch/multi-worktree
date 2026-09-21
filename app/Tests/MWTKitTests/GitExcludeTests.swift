import Foundation
import Testing
@testable import MWTKit

@Suite struct GitExcludeTests {
    @Test func createsInfoExcludeWithBothEntries() throws {
        let common = try TempDir.make()
        let added = try GitExclude.ensure(in: common)
        #expect(added == [".claude/settings.local.json", "CLAUDE.local.md"])
        let text = try String(contentsOf: common.appending(path: "info/exclude"), encoding: .utf8)
        #expect(text == ".claude/settings.local.json\nCLAUDE.local.md\n")
    }

    @Test func isIdempotentAndPreservesExistingLines() throws {
        let common = try TempDir.make()
        let file = common.appending(path: "info/exclude")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "*.swp\nCLAUDE.local.md".write(to: file, atomically: true, encoding: .utf8)
        #expect(try GitExclude.ensure(in: common) == [".claude/settings.local.json"])
        #expect(try GitExclude.ensure(in: common) == [])
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text == "*.swp\nCLAUDE.local.md\n.claude/settings.local.json\n")
    }

    @Test func writesToTheCommonDirOfALinkedWorktree() throws {
        let f = try GitFixture()
        let linked = f.root.appending(path: "linked")
        try f.git.worktreeAdd(.createNew(branch: "linked", base: "origin/main"), at: linked, in: f.repo)
        let common = try f.git.commonDir(of: linked)
        #expect(common.resolvingSymlinksInPath().path == f.repo.appending(path: ".git").resolvingSymlinksInPath().path)
        let excludeFile = f.repo.appending(path: ".git/info/exclude")
        let before = FileManager.default.fileExists(atPath: excludeFile.path)
            ? try String(contentsOf: excludeFile, encoding: .utf8)
            : ""
        #expect(try GitExclude.ensure(in: common) == [".claude/settings.local.json", "CLAUDE.local.md"])
        let text = try String(contentsOf: excludeFile, encoding: .utf8)
        #expect(text == before + ".claude/settings.local.json\nCLAUDE.local.md\n")
        try "x".write(to: linked.appending(path: "CLAUDE.local.md"), atomically: true, encoding: .utf8)
        #expect(try f.git.statusLines(in: linked).isEmpty)
    }
}
