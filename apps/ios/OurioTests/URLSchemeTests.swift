import Foundation
import MomentsInterface
import OurioShared
import Testing
import UsInterface
@testable import Billet

struct URLSchemeTests {
    /// Widgets open the app with ourio:// links (DeepLink); iOS routes them only to an app declaring the scheme.
    /// Invites sent before the rename, and the server's, still carry nooki://.
    @Test(arguments: ["ourio", "nooki"])
    func theAppDeclaresAndOpensTheScheme(_ scheme: String) {
        let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(scheme))
        #expect(DeepLink(url: URL(string: "\(scheme)://moments")!) == .moments)
        #expect(DeepLink(url: URL(string: "\(scheme)://invite/K7QM4R2XHP")!) == .invite("K7QM4R2XHP"))
    }
}
