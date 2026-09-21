import Foundation

public enum ClaudeUserState {
    public static func hasLocalMCPServers(forProject path: String, claudeJSON: URL) -> Bool {
        guard let data = try? Data(contentsOf: claudeJSON),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = root["projects"] as? [String: Any],
              let entry = projects[path] as? [String: Any],
              let servers = entry["mcpServers"] as? [String: Any]
        else { return false }
        return !servers.isEmpty
    }
}
