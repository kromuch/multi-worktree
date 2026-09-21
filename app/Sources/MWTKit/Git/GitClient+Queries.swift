import Foundation

public struct WorktreeInfo: Equatable, Sendable {
    public let path: String
    public let head: String
    public let branch: String?
    public let isDetached: Bool
    public let isPrunable: Bool
}

public enum WorktreeBranchPlan: Equatable, Sendable {
    case reuseLocal(String)
    case trackRemote(remote: String, branch: String)
    case createNew(branch: String, base: String)
}

public extension GitClient {
    func topLevel(of directory: URL) throws -> URL {
        URL(fileURLWithPath: try run(["rev-parse", "--show-toplevel"], in: directory))
    }

    func commonDir(of directory: URL) throws -> URL {
        URL(fileURLWithPath: try run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: directory))
    }

    func currentBranch(in directory: URL) -> String? {
        try? run(["symbolic-ref", "--quiet", "--short", "HEAD"], in: directory)
    }

    func remotes(in directory: URL) throws -> [String] {
        try run(["remote"], in: directory).split(separator: "\n").map(String.init)
    }

    func configuredRemote(forBranch branch: String, in directory: URL) -> String? {
        try? run(["config", "--get", "branch.\(branch).remote"], in: directory)
    }

    func remoteHead(remote: String, in directory: URL) -> String? {
        guard let full = try? run(["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remote)/HEAD"], in: directory) else { return nil }
        let prefix = remote + "/"
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
    }

    func setRemoteHeadAuto(remote: String, in directory: URL) -> Bool {
        succeeds(["remote", "set-head", remote, "--auto"], in: directory)
    }

    func fetch(remote: String, in directory: URL) -> Bool {
        succeeds(["fetch", "--quiet", remote], in: directory)
    }

    func commitExists(_ ref: String, in directory: URL) -> Bool {
        succeeds(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"], in: directory)
    }

    func localBranchExists(_ branch: String, in directory: URL) -> Bool {
        succeeds(["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"], in: directory)
    }

    func upstream(of branch: String, in directory: URL) -> String? {
        try? run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "\(branch)@{upstream}"], in: directory)
    }

    func revListCount(_ range: String, in directory: URL) -> Int? {
        guard let text = try? run(["rev-list", "--count", range], in: directory) else { return nil }
        return Int(text)
    }

    func worktreeAdd(_ plan: WorktreeBranchPlan, at path: URL, in directory: URL) throws {
        switch plan {
        case .reuseLocal(let branch):
            try run(["worktree", "add", path.path, branch], in: directory)
        case .trackRemote(let remote, let branch):
            try run(["worktree", "add", "--track", "-b", branch, path.path, "\(remote)/\(branch)"], in: directory)
        case .createNew(let branch, let base):
            try run(["worktree", "add", "--no-track", "-b", branch, path.path, base], in: directory)
        }
    }

    func worktreeRemove(_ path: URL, force: Bool, in directory: URL) throws {
        try run(["worktree", "remove"] + (force ? ["--force"] : []) + [path.path], in: directory)
    }

    func worktreePrune(in directory: URL) {
        _ = succeeds(["worktree", "prune"], in: directory)
    }

    func worktrees(in directory: URL) throws -> [WorktreeInfo] {
        let text = try run(["worktree", "list", "--porcelain"], in: directory)
        return text.components(separatedBy: "\n\n").compactMap { block in
            var path: String?
            var head = ""
            var branch: String?
            var detached = false
            var prunable = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst("worktree ".count)) }
                else if line.hasPrefix("HEAD ") { head = String(line.dropFirst("HEAD ".count)) }
                else if line.hasPrefix("branch ") { branch = String(line.dropFirst("branch ".count)).replacingOccurrences(of: "refs/heads/", with: "") }
                else if line == "detached" { detached = true }
                else if line.hasPrefix("prunable") { prunable = true }
            }
            guard let path else { return nil }
            return WorktreeInfo(path: path, head: head, branch: branch, isDetached: detached, isPrunable: prunable)
        }
    }

    func statusLines(in directory: URL) throws -> [String] {
        let result = try execute(["status", "--porcelain", "--untracked-files=all"], in: directory, environment: [:])
        guard result.succeeded else { throw GitError(arguments: ["status"], status: result.status, stderr: result.stderr) }
        return result.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func deleteBranch(_ branch: String, in directory: URL) throws {
        try run(["branch", "-D", branch], in: directory)
    }

    func isValidBranchName(_ branch: String) -> Bool {
        succeeds(["check-ref-format", "--branch", branch], in: nil)
    }

    func ignoredFiles(in directory: URL) throws -> [String] {
        let result = try execute(["ls-files", "--others", "--ignored", "--exclude-standard", "-z"], in: directory, environment: [:])
        guard result.succeeded else { throw GitError(arguments: ["ls-files"], status: result.status, stderr: result.stderr) }
        return result.stdout.split(separator: "\0").map(String.init)
    }
}
