import CryptoKit
import Foundation
import Testing
@testable import Billet

struct CatCoatTests {
    /// sha256 of billet-gpu's coat PLYs (coats/SHA256SUMS), which Ilya's PLY plus the shipped colours must rebuild.
    static let expected: [String: String] = [
        "Mochi-ginger": "41a838b2b7508d7dbdf71a8bcbdab1dbcf2cd7e038d7a18e9853a07df7a8c114",
        "MochiStanding-ginger": "a11409cbd072d4a9855708e6e507e64d60d84906f226d2d1759bc8e0e0d0d761",
        "Mochi-cream": "0b740549ff7497ad7606b5627eb969ec59516e3d4b368bf1c91b6df89a0c2cd3",
        "MochiStanding-cream": "a3e5877b9fb5cd09790662ffcbf4ffbc1aeabff76c82739c4f2b10fcc55c1c93",
        "Mochi-tuxedo": "06f78652fe54f6603f29cdded8577883f6953ca8504be8cd53e4d576b3052464",
        "MochiStanding-tuxedo": "3c3e6974d02039c3ed7079ee2153a467fab9c96ac6484cf9db63e08871127787",
        "Mochi-black": "e478b74296d0746753665883d32bb2c5c35ef584c580daa0b02d163bd3e5c030",
        "MochiStanding-black": "20f56e95fa5f577c7c341b3f67d55a82fc89942476f855572274c735dc5e3a48",
        "Mochi-calico": "5fc9176dddba1fc302b647d15666621b7b09af55e16981586315193ec285cd19",
        "MochiStanding-calico": "95585254d29fcfe8fa46c7fb181120d8c781591e8959df2e57fbe87e0ab5fb0a",
    ]

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test(arguments: CatCoat.poses, CatCoat.allCases.filter { $0 != .grey })
    func aCoatRebuildsBilletGPUsPLY(pose: String, coat: CatCoat) throws {
        #expect(Self.sha256(try coat.dressedPLY(pose)) == Self.expected["\(pose)-\(coat.rawValue)"])
    }

    @Test func aCoatsBundleHoldsItsPLYsBesideIlyasSkinsAndRigs() throws {
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
            guard coat != .grey else { continue }
            for model in ["Cat", "CatStanding"] {
                #expect(Bundle.main.url(forResource: "\(model)Color-\(coat.rawValue)", withExtension: "jpg") != nil)
            }
        }
    }
}
