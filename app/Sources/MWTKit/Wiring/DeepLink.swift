import Foundation

public enum DeepLink {
    public static func newSession(folder: URL, prompt: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/new"
        var items = [URLQueryItem(name: "folder", value: folder.path)]
        if let prompt { items.append(URLQueryItem(name: "q", value: prompt)) }
        components.queryItems = items
        return components.url!
    }
}
