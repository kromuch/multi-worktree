import Foundation

public enum WorktreeInclude {
    public static let fileName = ".worktreeinclude"

    public static func filesToCopy(git: any GitClient, original: URL, scratchDir: URL) throws -> [String] {
        let patternFile = original.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: patternFile.path) else { return [] }
        let ignored = Set(try git.ignoredFiles(in: original))
        let wholeDirs = try git.whollyIgnoredDirectories(in: original)
        let patterns = try reachablePatterns(at: patternFile)
        let unreachedDirs = wholeDirs.filter { dir in
            !patterns.contains { reaches(pattern: $0, directory: dir) }
        }
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
        return matching.filter { file in
            ignored.contains(file) && !unreachedDirs.contains { file.hasPrefix($0) }
        }.sorted()
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

    static func reachablePatterns(at file: URL) throws -> [String] {
        let text = try String(contentsOf: file, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.hasPrefix("#") && !$0.hasPrefix("!")
        }
    }

    static func reaches(pattern rawPattern: String, directory: String) -> Bool {
        var pattern = rawPattern
        if pattern.hasPrefix("/") { pattern.removeFirst() }
        let names = directory.split(separator: "/").map(String.init)
        let slashCount = pattern.filter { $0 == "/" }.count
        let unanchored = slashCount == 0 || (slashCount == 1 && pattern.hasSuffix("/"))
        if unanchored { pattern = "**/" + pattern }
        if pattern.hasPrefix("**/") {
            var first = String(pattern.dropFirst(3))
            if let slash = first.firstIndex(of: "/") { first = String(first[..<slash]) }
            return names.contains { globMatch(first, $0) }
        }
        let prefix = literalPrefix(pattern)
        guard !prefix.isEmpty else { return false }
        return directory.hasPrefix(prefix) || prefix.hasPrefix(directory)
    }

    static func literalPrefix(_ pattern: String) -> String {
        var result = ""
        for character in pattern {
            if character == "*" || character == "?" || character == "[" || character == "\\" { break }
            result.append(character)
        }
        return result
    }

    static func globMatch(_ pattern: String, _ name: String) -> Bool {
        pattern.withCString { patternPointer in
            name.withCString { namePointer in
                fnmatch(patternPointer, namePointer, 0) == 0
            }
        }
    }
}
