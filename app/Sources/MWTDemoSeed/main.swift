import Foundation
import MWTKit

struct DemoRepo {
    let name: String
    let commits: [(file: String, content: String, message: String)]
}

struct DemoSeedError: Error, CustomStringConvertible {
    let description: String
}

struct DemoSeed {
    static let defaultRoot = "/Users/Shared/mwt-demo"
    static let markerName = ".mwt-demo"
    static let feature = "feature/checkout-redesign"

    static let repos = [
        DemoRepo(name: "acme-web", commits: [
            ("README.md", "# Acme Web\n\nStorefront for Acme.\n", "Initial storefront"),
            (".gitignore", ".env\nnode_modules/\n", "Ignore local env"),
            (".worktreeinclude", ".env\n", "Carry .env into worktrees"),
            ("src/checkout.ts", "export const checkout = () => 'ok'\n", "Add checkout entry point"),
        ]),
        DemoRepo(name: "acme-api", commits: [
            ("README.md", "# Acme API\n", "Initial API"),
            ("src/orders.ts", "export const orders = []\n", "Add orders endpoint"),
        ]),
        DemoRepo(name: "acme-design-system", commits: [
            ("README.md", "# Acme Design System\n", "Initial tokens"),
            ("tokens/colors.json", "{\"brand\": \"#3355ee\"}\n", "Add brand colors"),
        ]),
        DemoRepo(name: "acme-docs", commits: [
            ("README.md", "# Acme Docs\n", "Initial docs"),
        ]),
    ]

    let root: URL
    let git: ShellGitClient

    init(root: URL) throws {
        self.root = root
        guard let gitPath = ToolEnvironment.fixed.findExecutable("git") else { throw DemoSeedError(description: "git not found") }
        let environment = [
            "GIT_CONFIG_GLOBAL": root.appending(path: "gitconfig").path,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
        ]
        git = ShellGitClient(gitPath: gitPath, runner: ProcessRunner(), baseEnvironment: environment)
    }

    var code: URL { root.appending(path: "code") }
    var home: URL { root.appending(path: "home") }

    func run() throws {
        try resetRoot()
        try """
        [user]
        \tname = Alex Demo
        \temail = alex@example.com
        [init]
        \tdefaultBranch = main
        [commit]
        \tgpgsign = false
        """.write(to: root.appending(path: "gitconfig"), atomically: true, encoding: .utf8)
        for repo in Self.repos { try create(repo) }
        try "API_URL=http://localhost:4000\n".write(to: code.appending(path: "acme-web/.env"), atomically: true, encoding: .utf8)

        let checkout = RepoGroup(name: "Acme Checkout", repos: [
            RepoEntry(path: code.appending(path: "acme-web").path, isMain: true),
            RepoEntry(path: code.appending(path: "acme-api").path, isMain: false),
            RepoEntry(path: code.appending(path: "acme-design-system").path, isMain: false),
        ])
        let docs = RepoGroup(name: "Acme Docs", repos: [
            RepoEntry(path: code.appending(path: "acme-docs").path, isMain: true),
            RepoEntry(path: code.appending(path: "acme-design-system").path, isMain: false),
        ])
        let store = ConfigStore(paths: MWTPaths(home: home))
        try store.saveGroups(GroupsFile(groups: [checkout, docs]))

        let feature = try FeatureName.parse(Self.feature)
        let preflights = Preflight(git: git).runAll(group: checkout, feature: feature)
        let env = SpinUpEnvironment(git: git, store: store, claudeJSON: home.appending(path: ".claude.json"),
                                    scratchDir: root.appending(path: "scratch"), open: { _ in }, now: { Date() })
        let result = try SpinUp(env: env).run(
            SpinUpRequest(group: checkout, feature: feature, baseChoices: [:], openClaude: false), preflights: preflights)
        guard result.report.hardError == nil, result.report.outcomes.allSatisfy({ $0.label == .created }) else {
            throw DemoSeedError(description: "demo spin-up failed: \(result.report)")
        }
    }

    func resetRoot() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            guard fm.fileExists(atPath: root.appending(path: Self.markerName).path) else {
                throw DemoSeedError(description: "\(root.path) exists and has no \(Self.markerName) marker; refusing to wipe it")
            }
            try fm.removeItem(at: root)
        }
        try fm.createDirectory(at: code, withIntermediateDirectories: true)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try Data().write(to: root.appending(path: Self.markerName))
    }

    func create(_ repo: DemoRepo) throws {
        let remote = root.appending(path: "remotes/\(repo.name).git")
        let clone = code.appending(path: repo.name)
        try git.run(["init", "--quiet", "--bare", "--initial-branch=main", remote.path])
        try git.run(["clone", "--quiet", remote.path, clone.path])
        try git.run(["symbolic-ref", "HEAD", "refs/heads/main"], in: clone)
        for commit in repo.commits {
            let file = clone.appending(path: commit.file)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try commit.content.write(to: file, atomically: true, encoding: .utf8)
            try git.run(["add", commit.file], in: clone)
            try git.run(["commit", "--quiet", "-m", commit.message], in: clone)
        }
        try git.run(["push", "--quiet", "-u", "origin", "main"], in: clone)
        try git.run(["remote", "set-head", "origin", "--auto"], in: clone)
    }
}

do {
    let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : DemoSeed.defaultRoot)
    try DemoSeed(root: root).run()
    print(root.path)
} catch {
    FileHandle.standardError.write(Data("MWTDemoSeed: \(error)\n".utf8))
    exit(1)
}
