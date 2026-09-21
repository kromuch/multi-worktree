import Testing
@testable import MWTKit

@Suite struct PreflightDecisionTests {
    func preflight(current: String? = "main", remoteDefaultExists: Bool = true, hasRemote: Bool = true,
                   localFeature: Bool = false, remoteFeature: Bool = false) -> RepoPreflight {
        RepoPreflight(repo: RepoEntry(path: "/r/ari", isMain: true), commonDir: "/r/ari/.git", remote: "origin",
                      hasRemote: hasRemote, defaultBranch: "main", currentBranch: current,
                      remoteDefaultExists: remoteDefaultExists, localFeatureBranchExists: localFeature,
                      remoteFeatureBranchExists: remoteFeature, notices: [])
    }

    @Test func defaultBaseIsRemoteTipWhenAvailable() {
        let d = BaseDecision.baseRef(for: preflight(), choice: .defaultBranch)
        #expect(d.ref == "origin/main")
        #expect(d.warning == nil)
    }

    @Test func defaultBaseFallsBackToLocalWithWarning() {
        let d = BaseDecision.baseRef(for: preflight(remoteDefaultExists: false), choice: .defaultBranch)
        #expect(d.ref == "main")
        #expect(d.warning?.contains("local main") == true)
    }

    @Test func currentBranchBaseUsesLocalTipWithoutWarning() {
        let d = BaseDecision.baseRef(for: preflight(current: "wip"), choice: .currentBranch)
        #expect(d.ref == "wip")
        #expect(d.warning == nil)
    }

    @Test func currentBranchBaseFallsBackWhenDetachedOrOnDefault() {
        let detached = BaseDecision.baseRef(for: preflight(current: nil), choice: .currentBranch)
        #expect(detached.ref == "origin/main")
        #expect(detached.warning?.contains("current branch") == true)
        let onDefault = BaseDecision.baseRef(for: preflight(current: "main"), choice: .currentBranch)
        #expect(onDefault.ref == "origin/main")
        #expect(onDefault.warning != nil)
    }

    @Test func offersCurrentBranchOnlyWhenOnAnotherBranch() {
        #expect(preflight(current: "wip").offersCurrentBranchBase)
        #expect(!preflight(current: "main").offersCurrentBranchBase)
        #expect(!preflight(current: nil).offersCurrentBranchBase)
    }

    @Test func branchResolutionOrder() {
        #expect(BranchResolution.plan(feature: "f", preflight: preflight(localFeature: true, remoteFeature: true), baseRef: "origin/main") == .reuseLocal("f"))
        #expect(BranchResolution.plan(feature: "f", preflight: preflight(remoteFeature: true), baseRef: "origin/main") == .trackRemote(remote: "origin", branch: "f"))
        #expect(BranchResolution.plan(feature: "f", preflight: preflight(), baseRef: "origin/main") == .createNew(branch: "f", base: "origin/main"))
    }
}
