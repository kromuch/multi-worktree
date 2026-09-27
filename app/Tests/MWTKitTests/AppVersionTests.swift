import Foundation
import Testing
@testable import MWTKit

@Suite struct AppVersionTests {
    @Test func parsesThreeAndTwoPartVersions() {
        #expect(AppVersion("0.1.1") == AppVersion(major: 0, minor: 1, patch: 1))
        #expect(AppVersion("v0.2.0") == AppVersion(major: 0, minor: 2, patch: 0))
        #expect(AppVersion("1.2") == AppVersion(major: 1, minor: 2, patch: 0))
        #expect(AppVersion(" 3.4.5\n") == AppVersion(major: 3, minor: 4, patch: 5))
    }

    @Test func rejectsMalformedVersions() {
        for text in ["", "v", "1", "1.2.3.4", "1.x.0", "-1.0.0", "1..0", "1.2.", "vv1.0.0", "1.2.3-rc1", "V1.0.0"] {
            #expect(AppVersion(text) == nil, "\(text)")
        }
    }

    @Test func ordersByMajorThenMinorThenPatch() throws {
        let v019 = try #require(AppVersion("0.1.9"))
        let v020 = try #require(AppVersion("0.2.0"))
        let v099 = try #require(AppVersion("0.9.9"))
        let v100 = try #require(AppVersion("1.0.0"))
        let v011 = try #require(AppVersion("0.1.1"))
        let v0110 = try #require(AppVersion("0.1.10"))
        #expect(v019 < v020)
        #expect(v099 < v100)
        #expect(v011 < v0110)
        #expect(!(v011 < v011))
    }

    @Test func descriptionIsThreePart() throws {
        #expect(try #require(AppVersion("1.2")).description == "1.2.0")
        #expect(try #require(AppVersion("v0.1.1")).description == "0.1.1")
    }
}
