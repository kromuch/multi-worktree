import Foundation
import Testing
@testable import MWTKit

@Suite struct KitInfoTests {
    @Test func versionIsSet() {
        #expect(KitInfo.version == "0.1.0")
    }

    @Test func tempDirHelperCreatesDirectory() throws {
        let dir = try TempDir.make()
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }
}
