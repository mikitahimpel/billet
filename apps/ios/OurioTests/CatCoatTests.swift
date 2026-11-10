import CryptoKit
import Foundation
import Testing
@testable import Billet

struct CatCoatTests {
    /// sha256 of billet-gpu's coat PLYs (coats/SHA256SUMS), which the original PLY
    /// plus the shipped colours must rebuild.
    static let expected: [String: String] = [
        "MochiStanding-ginger": "a11409cbd072d4a9855708e6e507e64d60d84906f226d2d1759bc8e0e0d0d761",
        "MochiStanding-cream": "a3e5877b9fb5cd09790662ffcbf4ffbc1aeabff76c82739c4f2b10fcc55c1c93",
        "MochiStanding-tuxedo": "3c3e6974d02039c3ed7079ee2153a467fab9c96ac6484cf9db63e08871127787",
        "MochiStanding-black": "20f56e95fa5f577c7c341b3f67d55a82fc89942476f855572274c735dc5e3a48",
        "MochiStanding-calico": "95585254d29fcfe8fa46c7fb181120d8c781591e8959df2e57fbe87e0ab5fb0a",
    ]

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test(arguments: CatCoat.poses, CatCoat.allCases.filter { $0 != .grey })
    func aCoatRebuildsBilletGPUsPLY(pose: String, coat: CatCoat) throws {
        #expect(Self.sha256(try coat.dressedPLY(pose)) == Self.expected["\(pose)-\(coat.rawValue)"])
    }

    @Test func aCoatsBundleHoldsItsPLYsBesideTheOriginalSkinsAndRigs() throws {
        let caches = URL.temporaryDirectory.appending(path: "coats-\(UUID().uuidString)")
        let bundle = try CatCoat.ginger.bundle(caches: caches)
        for pose in CatCoat.poses {
            let ply = try #require(bundle.url(forResource: pose, withExtension: "ply"))
            #expect(Self.sha256(try Data(contentsOf: ply)) == Self.expected["\(pose)-ginger"])
            let skin = try #require(bundle.url(forResource: pose, withExtension: "skin"))
            #expect(try Data(contentsOf: skin) == Data(contentsOf: Bundle.main.url(forResource: pose, withExtension: "skin")!))
            #expect(bundle.url(forResource: "\(pose).rig", withExtension: "json") != nil)
        }
        // A second call reuses what the first wrote.
        #expect(try CatCoat.ginger.bundle(caches: caches).bundleURL == bundle.bundleURL)
        #expect(try CatCoat.grey.bundle() == .main)
    }

    @Test func everyCoatHasItsCardAndMeshTextures() {
        for coat in CatCoat.allCases {
            #expect(Bundle.main.url(forResource: coat.portrait, withExtension: "png") != nil)
            #expect(Bundle.main.url(forResource: coat.avatar, withExtension: "png") != nil)
            guard coat != .grey else { continue }
            #expect(Bundle.main.url(forResource: "CatStandingColor-\(coat.rawValue)", withExtension: "jpg") != nil)
        }
    }
}
