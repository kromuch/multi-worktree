import Foundation

public enum DenyRules {
    public static func rules(forOriginal absolutePath: String) -> [String] {
        var trimmed = Substring(absolutePath)
        while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
        while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        return ["Read(//\(trimmed)/**)", "Edit(//\(trimmed)/**)"]
    }
}
