import Foundation

public enum OutcomeLabel: String, Codable, Sendable {
    case created
    case reused
    case skipped
    case warned
    case failed
    case kept
    case removed
}

public struct RepoOutcome: Equatable, Sendable {
    public var repoPath: String
    public var label: OutcomeLabel
    public var reasons: [String]

    public init(repoPath: String, label: OutcomeLabel, reasons: [String]) {
        self.repoPath = repoPath
        self.label = label
        self.reasons = reasons
    }
}

public struct RunReport: Equatable, Sendable {
    public var outcomes: [RepoOutcome]
    public var notes: [String]
    public var hardError: String?
    public var openedClaude: Bool

    public init() {
        outcomes = []
        notes = []
        hardError = nil
        openedClaude = false
    }
}
