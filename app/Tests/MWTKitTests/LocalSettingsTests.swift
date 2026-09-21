import Foundation
import Testing
@testable import MWTKit

@Suite struct LocalSettingsTests {
    func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func permissions(_ data: Data) throws -> [String: Any] {
        try #require(try json(data)["permissions"] as? [String: Any])
    }

    let update = LocalSettingsUpdate(
        additionalDirectoriesToRemove: [],
        additionalDirectoriesToAdd: ["/w/other"],
        denyToRemove: [],
        denyToAdd: DenyRules.rules(forOriginal: "/o/other"))

    @Test func createsFileContentFromNothing() throws {
        let outcome = try LocalSettings.apply(update, to: nil)
        #expect(!outcome.recreated)
        let p = try permissions(outcome.data)
        #expect(p["additionalDirectories"] as? [String] == ["/w/other"])
        #expect(p["deny"] as? [String] == ["Read(//o/other/**)", "Edit(//o/other/**)"])
        let text = String(decoding: outcome.data, as: UTF8.self)
        #expect(text.contains("Read(//o/other/**)"))
        #expect(!text.contains("\\/"))
    }

    @Test func preservesUnknownKeysAndUserEntries() throws {
        let existing = """
        {"model":"opus","permissions":{"allow":["Bash(ls *)"],"deny":["Read(~/.ssh/**)"],"additionalDirectories":["/user/dir"]}}
        """.data(using: .utf8)!
        let outcome = try LocalSettings.apply(update, to: existing)
        let root = try json(outcome.data)
        #expect(root["model"] as? String == "opus")
        let p = try permissions(outcome.data)
        #expect(p["allow"] as? [String] == ["Bash(ls *)"])
        #expect(p["deny"] as? [String] == ["Read(~/.ssh/**)", "Read(//o/other/**)", "Edit(//o/other/**)"])
        #expect(p["additionalDirectories"] as? [String] == ["/user/dir", "/w/other"])
    }

    @Test func removesPreviousToolSetAndDoesNotDuplicate() throws {
        let existing = """
        {"permissions":{"deny":["Read(//o/old/**)","Edit(//o/old/**)","Read(~/.ssh/**)"],"additionalDirectories":["/w/old","/w/other"]}}
        """.data(using: .utf8)!
        let rewire = LocalSettingsUpdate(
            additionalDirectoriesToRemove: ["/w/old", "/w/other"],
            additionalDirectoriesToAdd: ["/w/other", "/w/new"],
            denyToRemove: ["Read(//o/old/**)", "Edit(//o/old/**)"],
            denyToAdd: DenyRules.rules(forOriginal: "/o/new"))
        let p = try permissions(try LocalSettings.apply(rewire, to: existing).data)
        #expect(p["additionalDirectories"] as? [String] == ["/w/other", "/w/new"])
        #expect(p["deny"] as? [String] == ["Read(~/.ssh/**)", "Read(//o/new/**)", "Edit(//o/new/**)"])
    }

    @Test func invalidJSONIsRecreatedAndBackedUp() throws {
        let dir = try TempDir.make()
        let file = dir.appending(path: ".claude/settings.local.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{not json".write(to: file, atomically: true, encoding: .utf8)
        #expect(try LocalSettings.write(update, at: file) == true)
        #expect(try String(contentsOf: file.appendingPathExtension("bak"), encoding: .utf8) == "{not json")
        let p = try permissions(try Data(contentsOf: file))
        #expect(p["additionalDirectories"] as? [String] == ["/w/other"])
    }

    @Test func writeCreatesDirectoriesAndIsIdempotent() throws {
        let dir = try TempDir.make()
        let file = dir.appending(path: "wt/.claude/settings.local.json")
        #expect(try LocalSettings.write(update, at: file) == false)
        let first = try Data(contentsOf: file)
        #expect(try LocalSettings.write(update, at: file) == false)
        #expect(try Data(contentsOf: file) == first)
    }
}
