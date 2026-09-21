import Foundation

public struct RulesFileContext: Equatable, Sendable {
    public var feature: String
    public var mainRepoName: String
    public var siblingWorktrees: [String]
    public var unavailableSiblings: [String]

    public init(feature: String, mainRepoName: String, siblingWorktrees: [String], unavailableSiblings: [String]) {
        self.feature = feature
        self.mainRepoName = mainRepoName
        self.siblingWorktrees = siblingWorktrees
        self.unavailableSiblings = unavailableSiblings
    }
}

public enum RulesFile {
    public static let fileName = "CLAUDE.local.md"

    public static func render(_ context: RulesFileContext) -> String {
        var lines = [
            "# Worktree context (machine-local, do NOT commit)",
            "",
            "You are working in an isolated git worktree for feature `\(context.feature)`.",
            "- Main repo: `\(context.mainRepoName)` (this worktree). Never edit the original checkout of this repo.",
            "- Sibling repos available via additionalDirectories (each is ALSO a `\(context.feature)` worktree;",
            "  edit these, never the originals, which are denied):",
        ]
        if context.siblingWorktrees.isEmpty {
            lines.append("  - (none)")
        } else {
            lines += context.siblingWorktrees.map { "  - `\($0)`" }
        }
        if !context.unavailableSiblings.isEmpty {
            let names = context.unavailableSiblings.map { "`\($0)`" }.joined(separator: ", ")
            lines.append("- Siblings unavailable in this spin-up (creation failed): \(names)")
        }
        lines += [
            "- Do not commit `.claude/settings.local.json` or this `CLAUDE.local.md` (both are git-excluded).",
            "- Auto memory is shared with the main repo by Claude Code itself; nothing to configure.",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
