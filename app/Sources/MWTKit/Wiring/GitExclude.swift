import Foundation

public enum GitExclude {
    public static let entries = [".claude/settings.local.json", "CLAUDE.local.md"]

    @discardableResult
    public static func ensure(_ entries: [String] = entries, in commonDir: URL) throws -> [String] {
        let fm = FileManager.default
        let infoDir = commonDir.appending(path: "info")
        try fm.createDirectory(at: infoDir, withIntermediateDirectories: true)
        let file = infoDir.appending(path: "exclude")
        var text = fm.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : ""
        let present = Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = entries.filter { !present.contains($0) }
        guard !missing.isEmpty else { return [] }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += missing.joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
        return missing
    }
}
