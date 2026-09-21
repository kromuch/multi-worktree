import Foundation

public struct FeatureName: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case empty
        case tooLong
        case invalidCharacters
        case doubleDot
        case emptyPathComponent
        case leadingOrTrailingDotOrDash
    }

    public let branch: String
    public let segment: String

    static let maxLength = 100
    static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")

    public static func parse(_ raw: String) throws -> FeatureName {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ValidationError.empty }
        guard name.count <= maxLength else { throw ValidationError.tooLong }
        guard name.allSatisfy({ allowed.contains($0) }) else { throw ValidationError.invalidCharacters }
        guard !name.contains("..") else { throw ValidationError.doubleDot }
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            guard !component.isEmpty else { throw ValidationError.emptyPathComponent }
            let edges = [component.first!, component.last!]
            guard !edges.contains(".") && !edges.contains("-") else { throw ValidationError.leadingOrTrailingDotOrDash }
        }
        return FeatureName(branch: name, segment: name.replacingOccurrences(of: "/", with: "__"))
    }
}
