import Foundation
import Testing
@testable import MWTKit

@Suite struct WorktreeIncludeTests {
    func write(_ rel: String, _ content: String, in dir: URL) throws {
        let url = dir.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func selectsOnlyGitignoredFilesThatMatchPatterns() throws {
        let f = try GitFixture()
        try f.commit(file: ".gitignore", content: ".env\nbuild/\n*.log\nconfig/\n", message: "ignore")
        try f.commit(file: ".worktreeinclude", content: ".env\n.env.local\nconfig/secrets.json\n", message: "include")
        try write(".env", "SECRET=1\n", in: f.repo)
        try write(".env.local", "LOCAL=1\n", in: f.repo)
        try write("config/secrets.json", "{}\n", in: f.repo)
        try write("build/out.o", "x", in: f.repo)
        try write("app.log", "x", in: f.repo)
        let scratch = f.root.appending(path: "scratch")
        let files = try WorktreeInclude.filesToCopy(git: f.git, original: f.repo, scratchDir: scratch)
        #expect(files == [".env", "config/secrets.json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
    }

    @Test func noPatternFileMeansNothingToCopy() throws {
        let f = try GitFixture()
        try write(".env", "SECRET=1\n", in: f.repo)
        #expect(try WorktreeInclude.filesToCopy(git: f.git, original: f.repo, scratchDir: f.root.appending(path: "scratch")) == [])
    }

    @Test func copyRecreatesRelativePathsAndOverwrites() throws {
        let src = try TempDir.make()
        let dst = try TempDir.make()
        try write(".env", "SECRET=1\n", in: src)
        try write("config/secrets.json", "{}\n", in: src)
        try write("config/secrets.json", "old", in: dst)
        try WorktreeInclude.copy([".env", "config/secrets.json"], from: src, to: dst)
        #expect(try String(contentsOf: dst.appending(path: ".env"), encoding: .utf8) == "SECRET=1\n")
        #expect(try String(contentsOf: dst.appending(path: "config/secrets.json"), encoding: .utf8) == "{}\n")
    }
}
