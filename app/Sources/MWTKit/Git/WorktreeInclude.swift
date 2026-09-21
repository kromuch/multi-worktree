import Foundation

public enum WorktreeInclude {
    public static let fileName = ".worktreeinclude"

    public static func filesToCopy(git: any GitClient, original: URL, scratchDir: URL) throws -> [String] {
        let patternFile = original.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: patternFile.path) else { return [] }
        let ignored = Set(try git.ignoredFiles(in: original))
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        let scratchRepo = scratchDir.appending(path: "wti-\(UUID().uuidString).git")
        try git.run(["init", "--quiet", "--bare", scratchRepo.path])
        defer { try? FileManager.default.removeItem(at: scratchRepo) }
        let result = try git.execute(
            ["ls-files", "--others", "--ignored", "--exclude-from=\(patternFile.path)", "-z"],
            in: original,
            environment: ["GIT_DIR": scratchRepo.path, "GIT_WORK_TREE": original.path])
        guard result.succeeded else {
            throw GitError(arguments: ["ls-files", "--exclude-from"], status: result.status, stderr: result.stderr)
        }
        let matching = result.stdout.split(separator: "\0").map(String.init)
        return matching.filter { ignored.contains($0) }.sorted()
    }

    public static func copy(_ files: [String], from original: URL, to worktree: URL) throws {
        let fm = FileManager.default
        for relative in files {
            let source = original.appending(path: relative)
            let destination = worktree.appending(path: relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source, to: destination)
        }
    }
}
