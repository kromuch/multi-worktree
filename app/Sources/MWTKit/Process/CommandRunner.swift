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

public struct CommandTimeout: Error, Equatable, Sendable, CustomStringConvertible {
    public let executable: String
    public let seconds: Double

    public init(executable: String, seconds: Double) {
        self.executable = executable
        self.seconds = seconds
    }

    public var description: String { "\(executable) did not finish in \(Self.format(seconds)) s" }

    public static func format(_ seconds: Double) -> String {
        String(format: "%g", seconds)
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], cwd: URL?, extraEnvironment: [String: String],
             timeout: Duration?) throws -> CommandResult
}

public extension CommandRunning {
    func run(_ executable: String, _ arguments: [String], cwd: URL?, extraEnvironment: [String: String]) throws -> CommandResult {
        try run(executable, arguments, cwd: cwd, extraEnvironment: extraEnvironment, timeout: nil)
    }
}

final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class PipeDrain: @unchecked Sendable {
    let pipe = Pipe()
    let box = DataBox()
    let done = DispatchSemaphore(value: 0)

    func start() {
        Thread.detachNewThread { [self] in
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                if count > 0 {
                    box.append(Data(buffer[0..<count]))
                } else if count == 0 || errno != EINTR {
                    break
                }
            }
            done.signal()
        }
    }
}

public struct ProcessRunner: CommandRunning {
    static let drainGrace = 0.5

    public let environment: ToolEnvironment

    public init(environment: ToolEnvironment = .fixed) {
        self.environment = environment
    }

    public func run(_ executable: String, _ arguments: [String], cwd: URL?, extraEnvironment: [String: String],
                    timeout: Duration?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var env = environment.childEnvironment()
        for (key, value) in extraEnvironment { env[key] = value }
        process.environment = env
        let stdout = PipeDrain()
        let stderr = PipeDrain()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        stdout.start()
        stderr.start()

        if let timeout {
            let seconds = Self.seconds(timeout)
            if exited.wait(timeout: .now() + seconds) == .timedOut {
                Self.stop(process, exited: exited)
                throw CommandTimeout(executable: executable, seconds: seconds)
            }
            _ = stdout.done.wait(timeout: .now() + Self.drainGrace)
            _ = stderr.done.wait(timeout: .now() + Self.drainGrace)
        } else {
            stdout.done.wait()
            stderr.done.wait()
            exited.wait()
        }
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.box.data, as: UTF8.self),
            stderr: String(decoding: stderr.box.data, as: UTF8.self))
    }

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    static func stop(_ process: Process, exited: DispatchSemaphore) {
        process.terminate()
        if exited.wait(timeout: .now() + 1) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 0.5)
        }
    }
}
