import Foundation
import Testing
@testable import Billet

struct URLSchemeTests {
    /// The widgets open the app with nooki:// links (DeepLink); iOS only routes them to an app that declares the scheme.
    @Test func theAppDeclaresTheNookiScheme() {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("nooki"))
        #expect(DeepLink(url: URL(string: "nooki://moments")!) != nil)
    }
}
