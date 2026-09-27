import Foundation
import Testing
@testable import MWTKit

@Suite struct KitInfoTests {
    @Test func versionIsThreePartSemantic() throws {
        let version = try #require(AppVersion(KitInfo.version))
        #expect(version.description == KitInfo.version)
    }

    @Test func tempDirHelperCreatesDirectory() throws {
        let dir = try TempDir.make()
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }
}
