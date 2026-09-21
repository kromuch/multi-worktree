import Foundation
import Testing
@testable import MWTKit

@Suite struct ClaudeUserStateTests {
    @Test func detectsNonEmptyLocalMCPServers() throws {
        let file = try TempDir.make().appending(path: ".claude.json")
        try """
        {"projects":{"/a/ari":{"mcpServers":{"jira":{"type":"http"}}},"/a/none":{"mcpServers":{}},"/a/absent":{"allowedTools":[]}}}
        """.write(to: file, atomically: true, encoding: .utf8)
        #expect(ClaudeUserState.hasLocalMCPServers(forProject: "/a/ari", claudeJSON: file))
        #expect(!ClaudeUserState.hasLocalMCPServers(forProject: "/a/none", claudeJSON: file))
        #expect(!ClaudeUserState.hasLocalMCPServers(forProject: "/a/absent", claudeJSON: file))
        #expect(!ClaudeUserState.hasLocalMCPServers(forProject: "/a/unknown", claudeJSON: file))
    }

    @Test func missingOrInvalidFileIsFalse() throws {
        let dir = try TempDir.make()
        #expect(!ClaudeUserState.hasLocalMCPServers(forProject: "/a", claudeJSON: dir.appending(path: "missing.json")))
        let bad = dir.appending(path: "bad.json")
        try "nope".write(to: bad, atomically: true, encoding: .utf8)
        #expect(!ClaudeUserState.hasLocalMCPServers(forProject: "/a", claudeJSON: bad))
    }
}
