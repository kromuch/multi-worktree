import Testing
@testable import MWTKit

@Suite struct RulesFileTests {
    @Test func rendersSpecTemplateWithSiblingsAndUnavailable() {
        let text = RulesFile.render(RulesFileContext(
            feature: "NODE-1",
            mainRepoName: "ari",
            siblingWorktrees: ["/Users/me/.mwt/trees/NODE-1/other"],
            unavailableSiblings: ["broken"]))
        let expected = """
        # Worktree context (machine-local, do NOT commit)

        You are working in an isolated git worktree for feature `NODE-1`.
        - Main repo: `ari` (this worktree). Never edit the original checkout of this repo.
        - Sibling repos available via additionalDirectories (each is ALSO a `NODE-1` worktree;
          edit these, never the originals, which are denied):
          - `/Users/me/.mwt/trees/NODE-1/other`
        - Siblings unavailable in this spin-up (creation failed): `broken`
        - Do not commit `.claude/settings.local.json` or this `CLAUDE.local.md` (both are git-excluded).
        - Auto memory is shared with the main repo by Claude Code itself; nothing to configure.

        """
        #expect(text == expected)
    }

    @Test func omitsUnavailableSectionWhenEmptyAndMarksNoSiblings() {
        let text = RulesFile.render(RulesFileContext(feature: "f", mainRepoName: "m", siblingWorktrees: [], unavailableSiblings: []))
        #expect(!text.contains("unavailable"))
        #expect(text.contains("  - (none)\n"))
        #expect(RulesFile.fileName == "CLAUDE.local.md")
    }
}
