import Testing
@testable import MWTKit

@Suite struct FeatureNameTests {
    @Test func plainNameIsBranchAndSegment() throws {
        let f = try FeatureName.parse("NODE-1234-payments")
        #expect(f.branch == "NODE-1234-payments")
        #expect(f.segment == "NODE-1234-payments")
    }

    @Test func slashMapsToDoubleUnderscoreInSegment() throws {
        let f = try FeatureName.parse("feature/NODE-1")
        #expect(f.branch == "feature/NODE-1")
        #expect(f.segment == "feature__NODE-1")
    }

    @Test func trimsOuterWhitespace() throws {
        #expect(try FeatureName.parse("  abc ").branch == "abc")
    }

    @Test func rejectsEmpty() {
        #expect(throws: FeatureName.ValidationError.empty) { try FeatureName.parse("   ") }
    }

    @Test func rejectsTooLong() {
        #expect(throws: FeatureName.ValidationError.tooLong) {
            try FeatureName.parse(String(repeating: "a", count: 101))
        }
    }

    @Test func rejectsInnerWhitespaceAndNonASCII() {
        #expect(throws: FeatureName.ValidationError.invalidCharacters) { try FeatureName.parse("a b") }
        #expect(throws: FeatureName.ValidationError.invalidCharacters) { try FeatureName.parse("фіча") }
        #expect(throws: FeatureName.ValidationError.invalidCharacters) { try FeatureName.parse("a:b") }
        #expect(throws: FeatureName.ValidationError.invalidCharacters) { try FeatureName.parse("a\\b") }
    }

    @Test func rejectsDoubleDot() {
        #expect(throws: FeatureName.ValidationError.doubleDot) { try FeatureName.parse("a..b") }
    }

    @Test func rejectsEmptyPathComponent() {
        #expect(throws: FeatureName.ValidationError.emptyPathComponent) { try FeatureName.parse("a//b") }
        #expect(throws: FeatureName.ValidationError.emptyPathComponent) { try FeatureName.parse("/a") }
    }

    @Test func rejectsLeadingOrTrailingDotOrDash() {
        #expect(throws: FeatureName.ValidationError.leadingOrTrailingDotOrDash) { try FeatureName.parse(".a") }
        #expect(throws: FeatureName.ValidationError.leadingOrTrailingDotOrDash) { try FeatureName.parse("a-") }
        #expect(throws: FeatureName.ValidationError.leadingOrTrailingDotOrDash) { try FeatureName.parse("x/-a") }
    }

    @Test func allowsDotsUnderscoresInside() throws {
        #expect(try FeatureName.parse("v1.2_rc").segment == "v1.2_rc")
    }
}
