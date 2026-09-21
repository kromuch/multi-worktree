import Foundation
import Testing
@testable import MWTKit

@Suite struct DeepLinkTests {
    @Test func buildsNewSessionLink() throws {
        let url = DeepLink.newSession(folder: URL(fileURLWithPath: "/Users/me/.mwt/trees/f/ari"))
        #expect(url.scheme == "claude")
        #expect(url.host == "code")
        #expect(url.path == "/new")
        #expect(url.absoluteString.hasPrefix("claude://code/new?folder="))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items == [URLQueryItem(name: "folder", value: "/Users/me/.mwt/trees/f/ari")])
    }

    @Test func encodesSpacesAndOptionalPrompt() throws {
        let url = DeepLink.newSession(folder: URL(fileURLWithPath: "/Users/me/My Repo"), prompt: "hi there & bye")
        #expect(url.absoluteString.contains("folder=/Users/me/My%20Repo"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.count == 2)
        #expect(items[1] == URLQueryItem(name: "q", value: "hi there & bye"))
    }
}
