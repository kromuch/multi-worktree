import Foundation

public struct CommandResult: Equatable, Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { status == 0 }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], cwd: URL?, extraEnvironment: [String: String]) throws -> CommandResult
}

public enum ToolEnvironment {
    public static let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    public static let gitCandidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]

    public static func childEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["PATH"] = path
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        return env
    }

    public static func resolveGit() -> String? {
        gitCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

final class DataBox: @unchecked Sendable {
    var data = Data()
}

public struct ProcessRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], cwd: URL?, extraEnvironment: [String: String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var env = ToolEnvironment.childEnvironment()
        for (key, value) in extraEnvironment { env[key] = value }
        process.environment = env
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let stderrBox = DataBox()
        let stderrDescriptor = stderrPipe.fileHandleForReading.fileDescriptor
        let group = DispatchGroup()
        group.enter()
        Thread.detachNewThread {
            stderrBox.data = FileHandle(fileDescriptor: stderrDescriptor).readDataToEndOfFile()
            group.leave()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self))
    }
}
