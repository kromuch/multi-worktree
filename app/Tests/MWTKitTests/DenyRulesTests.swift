import Testing
@testable import MWTKit

@Suite struct DenyRulesTests {
    @Test func producesReadAndEditRulesWithDoubleSlashAnchor() {
        #expect(DenyRules.rules(forOriginal: "/Users/me/other-repo") == [
            "Read(//Users/me/other-repo/**)",
            "Edit(//Users/me/other-repo/**)",
        ])
    }

    @Test func neverEmitsTripleSlashOrWriteRules() {
        let rules = DenyRules.rules(forOriginal: "/Users/me/other-repo/")
        #expect(rules.allSatisfy { !$0.contains("///") })
        #expect(rules.allSatisfy { !$0.hasPrefix("Write(") })
        #expect(rules == ["Read(//Users/me/other-repo/**)", "Edit(//Users/me/other-repo/**)"])
    }
}
