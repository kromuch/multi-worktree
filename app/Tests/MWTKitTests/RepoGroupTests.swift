import Foundation
import Testing
@testable import MWTKit

@Suite struct RepoGroupTests {
    let main = RepoEntry(path: "/Users/me/ari", isMain: true)
    let other = RepoEntry(path: "/Users/me/other-repo", isMain: false)

    @Test func validGroupPasses() throws {
        try RepoGroup(name: "set", repos: [main, other]).validate()
    }

    @Test func basenameIsLastPathComponent() {
        #expect(other.basename == "other-repo")
    }

    @Test func mainAndSiblingsAreSplit() {
        let g = RepoGroup(name: "set", repos: [other, main])
        #expect(g.main == main)
        #expect(g.siblings == [other])
    }

    @Test func rejectsEmptyName() {
        #expect(throws: GroupValidationError.emptyName) {
            try RepoGroup(name: " ", repos: [main]).validate()
        }
    }

    @Test func rejectsNoRepos() {
        #expect(throws: GroupValidationError.noRepos) {
            try RepoGroup(name: "set", repos: []).validate()
        }
    }

    @Test func rejectsNoMain() {
        #expect(throws: GroupValidationError.noMain) {
            try RepoGroup(name: "set", repos: [other]).validate()
        }
    }

    @Test func rejectsTwoMains() {
        let secondMain = RepoEntry(path: "/Users/me/x", isMain: true)
        #expect(throws: GroupValidationError.multipleMains) {
            try RepoGroup(name: "set", repos: [main, secondMain]).validate()
        }
    }

    @Test func rejectsRelativePath() {
        let rel = RepoEntry(path: "relative/dir", isMain: false)
        #expect(throws: GroupValidationError.relativePath("relative/dir")) {
            try RepoGroup(name: "set", repos: [main, rel]).validate()
        }
    }

    @Test func rejectsDuplicateBasenames() {
        let clash = RepoEntry(path: "/Users/elsewhere/ari", isMain: false)
        #expect(throws: GroupValidationError.duplicateBasename("ari")) {
            try RepoGroup(name: "set", repos: [main, clash]).validate()
        }
    }

    @Test func groupsFileRoundTrips() throws {
        let file = GroupsFile(groups: [RepoGroup(name: "set", repos: [main, other])])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(GroupsFile.self, from: data)
        #expect(decoded == file)
        #expect(decoded.version == 1)
    }
}
