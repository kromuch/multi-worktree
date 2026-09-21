import Testing
@testable import MWTKit

@Suite struct TearDownRulesTests {
    @Test func missingLocalBranchIsAlreadyGone() {
        #expect(TearDownRules.decide(BranchState(localExists: false, remoteBranchExists: true, aheadOfRemote: 0, aheadOfDefault: 0)) == .alreadyGone)
    }

    @Test func fullyPushedIsDeleted() {
        let d = TearDownRules.decide(BranchState(localExists: true, remoteBranchExists: true, aheadOfRemote: 0, aheadOfDefault: 3))
        #expect(d == .delete(reason: "fully pushed"))
    }

    @Test func nothingBeyondDefaultIsDeleted() {
        let d = TearDownRules.decide(BranchState(localExists: true, remoteBranchExists: false, aheadOfRemote: nil, aheadOfDefault: 0))
        #expect(d == .delete(reason: "no commits beyond the default branch"))
    }

    @Test func unpushedCommitsAreKept() {
        let d = TearDownRules.decide(BranchState(localExists: true, remoteBranchExists: true, aheadOfRemote: 2, aheadOfDefault: 2))
        #expect(d == .keep(reason: "unpushed commits"))
    }

    @Test func erroringChecksKeep() {
        let d = TearDownRules.decide(BranchState(localExists: true, remoteBranchExists: false, aheadOfRemote: nil, aheadOfDefault: nil))
        #expect(d == .keep(reason: "no remote branch and the default-branch check was unavailable"))
    }
}
