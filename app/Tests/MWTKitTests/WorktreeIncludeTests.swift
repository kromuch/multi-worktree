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

struct WorktreeIncludeCase: Sendable {
    let name: String
    let gitignore: [String]
    let worktreeinclude: [String]
    let tracked: [String]
    let untracked: [String]
    let copies: [String]

    init(_ name: String, gitignore: [String], worktreeinclude: [String], tracked: [String] = [], untracked: [String], copies: [String]) {
        self.name = name
        self.gitignore = gitignore
        self.worktreeinclude = worktreeinclude
        self.tracked = tracked
        self.untracked = untracked
        self.copies = copies
    }
}

@Suite struct WorktreeIncludeRuleTests {
    static let cases: [WorktreeIncludeCase] = [
        WorktreeIncludeCase(
            "A",
            gitignore: [".env", "*.local", "node_modules/", ".claude/", "secrets/", "build/", "cache/"],
            worktreeinclude: [".env", "*.local", "**/.claude/skills/*.md", "secrets/", "build/out/", "node_modules/pkg/local.json"],
            untracked: [".env", "sub/.env", "sub/app.local", "node_modules/pkg/.env", "node_modules/pkg/local.json", ".claude/skills/x.md", ".claude/other.md", "secrets/key.txt", "secrets/deep/token.txt", "build/out/app.cfg", "build/tmp/junk.cfg", "cache/x.local"],
            copies: [".claude/skills/x.md", ".env", "build/out/app.cfg", "node_modules/pkg/.env", "node_modules/pkg/local.json", "secrets/deep/token.txt", "secrets/key.txt", "sub/.env", "sub/app.local"]),
        WorktreeIncludeCase(
            "A0",
            gitignore: [".env", "vendor/", "node_modules/", ".claude/", "secrets/"],
            worktreeinclude: [".env", "**/config.json", "**/.claude/skills/*.md", "secrets/"],
            tracked: ["config.json"],
            untracked: [".env", "sub/.env", "vendor/a/config.json", "node_modules/pkg/.env", ".claude/skills/x.md", "secrets/key.txt"],
            copies: [".claude/skills/x.md", ".env", "secrets/key.txt", "sub/.env"]),
        WorktreeIncludeCase(
            "B",
            gitignore: ["vendor/", "other/*.json"],
            worktreeinclude: ["**/config.json", "**/vendor/c/*.json"],
            untracked: ["vendor/a/config.json", "vendor/c/x.json", "nested/vendor/c/y.json", "nested/vendor/a/config.json", "other/config.json"],
            copies: ["vendor/a/config.json", "vendor/c/x.json", "nested/vendor/c/y.json", "nested/vendor/a/config.json", "other/config.json"]),
        WorktreeIncludeCase(
            "C",
            gitignore: ["vendor/", ".env"],
            worktreeinclude: ["vendor/**/settings.json", ".env"],
            untracked: ["vendor/b/settings.json", "vendor/x/.env", ".env"],
            copies: ["vendor/b/settings.json", "vendor/x/.env", ".env"]),
        WorktreeIncludeCase(
            "D",
            gitignore: ["secrets/", "*.key"],
            worktreeinclude: ["*.key", "!old.key", "secrets/", "!secrets/skip.txt"],
            untracked: ["a.key", "old.key", "secrets/keep.txt", "secrets/skip.txt"],
            copies: ["a.key", "secrets/keep.txt", "secrets/skip.txt"]),
        WorktreeIncludeCase(
            "E",
            gitignore: ["node_modules/"],
            worktreeinclude: ["**/node_modules/pkg/*.txt", "**/pkg/*.md"],
            untracked: ["node_modules/pkg/readme.txt", "node_modules/pkg/notes.md", "node_modules/other/readme.txt"],
            copies: ["node_modules/pkg/notes.md", "node_modules/pkg/readme.txt"]),
        WorktreeIncludeCase(
            "F",
            gitignore: ["node_modules/"],
            worktreeinclude: ["**/pkg/*.md"],
            untracked: ["node_modules/pkg/notes.md"],
            copies: []),
        WorktreeIncludeCase(
            "G",
            gitignore: ["cache/"],
            worktreeinclude: ["cache"],
            untracked: ["cache/x.local", "cache/deep/y.bin"],
            copies: ["cache/x.local", "cache/deep/y.bin"]),
        WorktreeIncludeCase(
            "H",
            gitignore: ["node_modules/"],
            worktreeinclude: ["node_*/pkg/*.txt"],
            untracked: ["node_modules/pkg/readme.txt"],
            copies: ["node_modules/pkg/readme.txt"]),
        WorktreeIncludeCase(
            "I",
            gitignore: ["node_modules/"],
            worktreeinclude: ["*/pkg/*.txt"],
            untracked: ["node_modules/pkg/readme.txt"],
            copies: []),
        WorktreeIncludeCase(
            "J",
            gitignore: ["vendor/"],
            worktreeinclude: ["a/**/config.json"],
            untracked: ["a/b/vendor/x/config.json"],
            copies: ["a/b/vendor/x/config.json"]),
        WorktreeIncludeCase(
            "K",
            gitignore: ["vendor/"],
            worktreeinclude: ["**/vendor"],
            untracked: ["vendor/x/a.json", "nested/vendor/y.json"],
            copies: ["vendor/x/a.json", "nested/vendor/y.json"]),
        WorktreeIncludeCase(
            "L",
            gitignore: ["vendor/"],
            worktreeinclude: ["**/x/*.json"],
            untracked: ["vendor/x/a.json"],
            copies: []),
        WorktreeIncludeCase(
            "M",
            gitignore: ["vendor/"],
            worktreeinclude: ["vendor/x/", "**/*.json"],
            untracked: ["vendor/x/a.json", "vendor/y/b.json", "top.json"],
            copies: ["vendor/x/a.json", "vendor/y/b.json"]),
        WorktreeIncludeCase(
            "N",
            gitignore: ["deps/"],
            worktreeinclude: ["deps/**"],
            untracked: ["deps/a.txt", "deps/b/c.txt"],
            copies: ["deps/a.txt", "deps/b/c.txt"]),
        WorktreeIncludeCase(
            "O",
            gitignore: ["node_modules/"],
            worktreeinclude: ["node"],
            untracked: ["node_modules/pkg/node"],
            copies: []),
        WorktreeIncludeCase(
            "P",
            gitignore: ["node_modules/"],
            worktreeinclude: ["**/node_*/pkg/x.txt"],
            untracked: ["node_modules/pkg/x.txt"],
            copies: ["node_modules/pkg/x.txt"]),
        WorktreeIncludeCase(
            "Q",
            gitignore: [".env.d/"],
            worktreeinclude: [".env"],
            untracked: [".env.d/.env"],
            copies: []),
        WorktreeIncludeCase(
            "S",
            gitignore: ["node_modules/"],
            worktreeinclude: ["/node_modules/pkg/*.txt"],
            untracked: ["node_modules/pkg/readme.txt"],
            copies: ["node_modules/pkg/readme.txt"]),
        WorktreeIncludeCase(
            "T",
            gitignore: ["node_modules/"],
            worktreeinclude: ["node_modules/pk"],
            untracked: ["node_modules/pk", "node_modules/pkg/readme.txt"],
            copies: ["node_modules/pk"]),
        WorktreeIncludeCase(
            "U",
            gitignore: ["vendor/"],
            worktreeinclude: ["vendor"],
            untracked: ["vendor/a.txt"],
            copies: ["vendor/a.txt"]),
        WorktreeIncludeCase(
            "V",
            gitignore: ["out/"],
            worktreeinclude: ["**/out/**/*.map"],
            untracked: ["out/a/b.map"],
            copies: ["out/a/b.map"]),
    ]

    func write(_ rel: String, in dir: URL) throws {
        let url = dir.appending(path: rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x\n".write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func reachUnanchoredMatchesAnyName() {
        #expect(WorktreeInclude.reaches(pattern: "vendor", directory: "vendor/"))
        #expect(WorktreeInclude.reaches(pattern: "vendor", directory: "nested/vendor/"))
        #expect(WorktreeInclude.reaches(pattern: "secrets/", directory: "secrets/"))
        #expect(WorktreeInclude.reaches(pattern: "*.local", directory: "app.local/"))
        #expect(WorktreeInclude.reaches(pattern: "*.local", directory: "config/") == false)
        #expect(WorktreeInclude.reaches(pattern: "node", directory: "node_modules/") == false)
        #expect(WorktreeInclude.reaches(pattern: ".env", directory: ".env.d/") == false)
    }

    @Test func reachGlobstarUsesFirstName() {
        #expect(WorktreeInclude.reaches(pattern: "**/vendor", directory: "nested/vendor/"))
        #expect(WorktreeInclude.reaches(pattern: "**/node_*/pkg/x.txt", directory: "node_modules/"))
        #expect(WorktreeInclude.reaches(pattern: "**/out/**/*.map", directory: "out/"))
        #expect(WorktreeInclude.reaches(pattern: "**/x/*.json", directory: "vendor/") == false)
        #expect(WorktreeInclude.reaches(pattern: "**/config.json", directory: "vendor/") == false)
    }

    @Test func reachAnchoredUsesLiteralPrefix() {
        #expect(WorktreeInclude.reaches(pattern: "node_modules/pk", directory: "node_modules/"))
        #expect(WorktreeInclude.reaches(pattern: "node_modules/pkg/*.txt", directory: "node_modules/"))
        #expect(WorktreeInclude.reaches(pattern: "vendor/x/", directory: "vendor/"))
        #expect(WorktreeInclude.reaches(pattern: "build/out/", directory: "build/"))
        #expect(WorktreeInclude.reaches(pattern: "a/**/config.json", directory: "a/b/vendor/"))
        #expect(WorktreeInclude.reaches(pattern: "node_*/pkg/*.txt", directory: "node_modules/"))
    }

    @Test func reachEmptyPrefixNeverReaches() {
        #expect(WorktreeInclude.reaches(pattern: "*/pkg/*.txt", directory: "node_modules/") == false)
    }

    @Test func reachDropsLeadingSlash() {
        #expect(WorktreeInclude.reaches(pattern: "/node_modules/pkg/*.txt", directory: "node_modules/"))
        #expect(WorktreeInclude.reaches(pattern: "/vendor/x/*.json", directory: "out/") == false)
    }

    @Test(arguments: cases) func reproducesClaudeRule(_ testCase: WorktreeIncludeCase) throws {
        let f = try GitFixture()
        try f.commit(file: ".gitignore", content: testCase.gitignore.joined(separator: "\n") + "\n", message: "ignore")
        try f.commit(file: ".worktreeinclude", content: testCase.worktreeinclude.joined(separator: "\n") + "\n", message: "include")
        for path in testCase.tracked {
            try f.commit(file: path, content: "x\n", message: "track")
        }
        for path in testCase.untracked {
            try write(path, in: f.repo)
        }
        let scratch = f.root.appending(path: "scratch")
        let files = try WorktreeInclude.filesToCopy(git: f.git, original: f.repo, scratchDir: scratch)
        #expect(files == testCase.copies.sorted(), "case \(testCase.name)")
    }
}
