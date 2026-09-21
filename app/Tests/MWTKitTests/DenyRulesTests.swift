import Testing
@testable import MWTKit

@Suite struct DenyRulesTests {
    @Test func producesReadAndEditRulesWithDoubleSlashAnchor() {
        #expect(DenyRules.rules(forOriginal: "/Users/rk/other-repo") == [
            "Read(//Users/rk/other-repo/**)",
            "Edit(//Users/rk/other-repo/**)",
        ])
    }

    @Test func neverEmitsTripleSlashOrWriteRules() {
        let rules = DenyRules.rules(forOriginal: "/Users/rk/other-repo/")
        #expect(rules.allSatisfy { !$0.contains("///") })
        #expect(rules.allSatisfy { !$0.hasPrefix("Write(") })
        #expect(rules == ["Read(//Users/rk/other-repo/**)", "Edit(//Users/rk/other-repo/**)"])
    }
}
