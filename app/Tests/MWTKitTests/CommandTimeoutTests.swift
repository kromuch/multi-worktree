import Foundation
import Testing
@testable import MWTKit

@Suite struct CommandTimeoutTests {
    let runner = ProcessRunner()

    @Test func childThatOutlivesTheTimeoutIsStoppedAndReported() throws {
        let start = Date()
        #expect(throws: CommandTimeout(executable: "/bin/sleep", seconds: 0.5)) {
            try runner.run("/bin/sleep", ["10"], cwd: nil, extraEnvironment: [:], timeout: .milliseconds(500))
        }
        #expect(Date().timeIntervalSince(start) < 2.5)
    }

    @Test func descendantHoldingStdoutDoesNotBlockAFinishedChild() throws {
        let start = Date()
        let r = try runner.run("/bin/sh", ["-c", "sleep 10 & echo started"], cwd: nil, extraEnvironment: [:], timeout: .seconds(3))
        #expect(r.succeeded)
        #expect(r.stdout == "started\n")
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func timeoutDescriptionNamesTheExecutableAndSeconds() {
        #expect(CommandTimeout(executable: "/bin/zsh", seconds: 5).description == "/bin/zsh did not finish in 5 s")
        #expect(CommandTimeout(executable: "/bin/zsh", seconds: 0.5).description == "/bin/zsh did not finish in 0.5 s")
    }
}
