import Foundation

public struct GitError: Error, Equatable, Sendable {
    public let arguments: [String]
    public let status: Int32
    public let stderr: String

    public init(arguments: [String], status: Int32, stderr: String) {
        self.arguments = arguments
        self.status = status
        self.stderr = stderr
    }
}

public protocol GitClient: Sendable {
    func execute(_ arguments: [String], in directory: URL?, environment: [String: String]) throws -> CommandResult
}

public extension GitClient {
    @discardableResult
    func run(_ arguments: [String], in directory: URL? = nil, environment: [String: String] = [:]) throws -> String {
        let result = try execute(arguments, in: directory, environment: environment)
        guard result.succeeded else {
            throw GitError(arguments: arguments, status: result.status, stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func succeeds(_ arguments: [String], in directory: URL? = nil) -> Bool {
        ((try? execute(arguments, in: directory, environment: [:]))?.succeeded) ?? false
    }
}
