import Foundation
import Testing
@testable import MWTKit

@Suite struct ConfigStoreTests {
    func makeStore() throws -> (ConfigStore, URL) {
        let home = try TempDir.make()
        return (ConfigStore(paths: MWTPaths(home: home)), home)
    }

    func sampleManifest(segment: String = "NODE-1", feature: String = "NODE-1") -> FeatureManifest {
        FeatureManifest(
            feature: feature,
            segment: segment,
            group: "set",
            createdAt: Date(timeIntervalSince1970: 1_758_400_000),
            mainWorktree: "/Users/me/.mwt/trees/\(segment)/ari",
            repos: [
                ManifestRepo(path: "/Users/me/ari", worktree: "/Users/me/.mwt/trees/\(segment)/ari", isMain: true,
                             remote: "origin", defaultBranch: "main", baseRef: "origin/main",
                             branchCreated: true, status: .created),
                ManifestRepo(path: "/Users/me/other", worktree: "/Users/me/.mwt/trees/\(segment)/other", isMain: false,
                             remote: "origin", defaultBranch: "master", baseRef: "origin/master",
                             branchCreated: false, status: .reused),
                ManifestRepo(path: "/Users/me/broken", worktree: "/Users/me/.mwt/trees/\(segment)/broken", isMain: false,
                             remote: nil, defaultBranch: nil, baseRef: nil,
                             branchCreated: false, status: .failed),
            ],
            denyEntries: ["Read(//Users/me/other/**)", "Edit(//Users/me/other/**)"])
    }

    @Test func pathsFollowSpecLayout() {
        let p = MWTPaths(home: URL(fileURLWithPath: "/Users/me"))
        #expect(p.groupsFile.path == "/Users/me/.mwt/groups.json")
        #expect(p.manifestURL(segment: "feat__x").path == "/Users/me/.mwt/features/feat__x.json")
        #expect(p.worktreeURL(segment: "feat__x", basename: "ari").path == "/Users/me/.mwt/trees/feat__x/ari")
        #expect(p.treeDir(segment: "feat__x").path == "/Users/me/.mwt/trees/feat__x")
    }

    @Test func missingGroupsFileLoadsEmpty() throws {
        let (store, _) = try makeStore()
        #expect(try store.loadGroups() == GroupsFile(groups: []))
    }

    @Test func groupsRoundTripAndAreValidatedOnSave() throws {
        let (store, home) = try makeStore()
        let group = RepoGroup(name: "set", repos: [RepoEntry(path: "/a/ari", isMain: true)])
        try store.saveGroups(GroupsFile(groups: [group]))
        #expect(FileManager.default.fileExists(atPath: home.appending(path: ".mwt/groups.json").path))
        #expect(try store.loadGroups().groups == [group])
        #expect(throws: GroupValidationError.noMain) {
            try store.saveGroups(GroupsFile(groups: [RepoGroup(name: "bad", repos: [RepoEntry(path: "/a/b", isMain: false)])]))
        }
    }

    @Test func manifestRoundTripsWithISODates() throws {
        let (store, home) = try makeStore()
        let m = sampleManifest()
        try store.saveManifest(m)
        let raw = try String(contentsOf: home.appending(path: ".mwt/features/NODE-1.json"), encoding: .utf8)
        #expect(raw.contains("\"createdAt\" : \"2025-09-20T20:26:40Z\""))
        #expect(try store.loadManifest(segment: "NODE-1") == m)
        #expect(try store.loadManifest(segment: "nope") == nil)
    }

    @Test func listAndDeleteManifests() throws {
        let (store, _) = try makeStore()
        try store.saveManifest(sampleManifest(segment: "a", feature: "a"))
        try store.saveManifest(sampleManifest(segment: "b", feature: "b"))
        #expect(try store.listManifests().map(\.segment).sorted() == ["a", "b"])
        try store.deleteManifest(segment: "a")
        #expect(try store.listManifests().map(\.segment) == ["b"])
        try store.deleteManifest(segment: "a")
    }

    @Test func listManifestsSkipsUndecodableFiles() throws {
        let (store, home) = try makeStore()
        try store.saveManifest(sampleManifest(segment: "good", feature: "good"))
        let garbage = home.appending(path: ".mwt/features/garbage.json")
        try "this is not a manifest".write(to: garbage, atomically: true, encoding: .utf8)
        #expect(try store.listManifests().map(\.segment) == ["good"])
    }

    @Test func managedAdditionalDirectoriesAreNonMainCreatedOrReused() {
        let m = sampleManifest()
        #expect(m.managedAdditionalDirectories == ["/Users/me/.mwt/trees/NODE-1/other"])
        #expect(m.allRemoved == false)
        #expect(m.repoIndex(path: "/Users/me/other") == 1)
    }
}
