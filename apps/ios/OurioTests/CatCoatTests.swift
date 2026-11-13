import CryptoKit
import Foundation
import Testing
@testable import Billet

struct CatCoatTests {
    /// sha256 of the original PLY with each splat's `f_dc` replaced by the shipped half float, printed by
    /// `scripts/coats/coat-colours.py`; billet-gpu's coat PLYs (coats/SHA256SUMS) differ from these in `f_dc` by at most 0.002.
    static let expected: [String: String] = [
        "Mochi-ginger": "36eb64432b268b65fd95bec4196a961530fb9fef687b27fd72c87db82b5a2db2",
        "MochiStanding-ginger": "a1ce18891c7f7a174226192b46927540514f2b0ad279328dcef91a49a23e1b46",
        "Mochi-cream": "93096b26b504427652646282a8fbf701f2aca1840652489a30e70636cb37a821",
        "MochiStanding-cream": "db3621d9a2d55a78155dfcb0db3d5873dd88d9d00d9642c443241b8e08be4394",
        "Mochi-tuxedo": "ebc7b699cc7cebbc56b00c22d4921934115f65443dfd482f778606f98d3b01e5",
        "MochiStanding-tuxedo": "68673865e817aa32dda88738178d1a06c7209d61ea9a41264c829d7c2473426f",
        "Mochi-black": "a27be6b1164429985eadeee421636cff4375e2c4a0a7b8f3b31a8a4b2fb1709b",
        "MochiStanding-black": "381c8f0cb067b794006cc78bbbcdd716a33386da3c52ef17617a51f6b01722de",
        "Mochi-calico": "fc9bccd7b876a5e83fba1548f54f5820e5897a5226b95946ec46c0ce010a988f",
        "MochiLoaf-ginger": "d412ad77d0026fd87473dcb422efce4921a2237e4919d83a265d399c09a85056",
        "MochiLoaf-cream": "959568a166dbc831ef0768d7e13723eab4ed0a5a46b13fbafeac58b2747dbd5f",
        "MochiLoaf-tuxedo": "afc3089e2cc8e025681d85a950ed6eabfb5e2727cd639e9ea768a67dd9c9a85d",
        "MochiLoaf-black": "e97157ed7c607f047eb2475ad47328f7318672ea41fc5b8bf03f3ab5bfa81b7b",
        "MochiLoaf-calico": "fec37524ca2521d70447efc1f054bd49db86a0ab142cc0dc5f5e54b976e1dc94",
        "MochiSleep-ginger": "444f0a64b566e8b5c874caf650b2e6bad195f456cbfae7ec9196772d8241891f",
        "MochiSleep-cream": "8513e95e6e46f4fbb4e36bafac9fd7eef8232f343d5773e8ff025301533d5684",
        "MochiSleep-tuxedo": "1f5fd1d0d58806760025d8a578d929bf17e05c16de43e08b8e962d9f12427302",
        "MochiSleep-black": "58ca558a6c82eb2984203018519d54009e328c9234c22846a319c9b31afbb628",
        "MochiSleep-calico": "c1e05ecfc47a2c6e77368ef50ebdef41402db74b168acee0369752a6b4589d44",
        "MochiStanding-calico": "14e4472e71774e85812376f2f53f08d1609138845c10d2d78f0dcf53b314fe69",
    ]

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test(arguments: CatCoat.poses, CatCoat.allCases.filter { $0 != .grey })
    func aCoatKeepsEverythingButTheColoursOfTheOriginalPLY(pose: String, coat: CatCoat) throws {
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
            for model in ["Cat", "CatStanding"] {
                #expect(Bundle.main.url(forResource: "\(model)Color-\(coat.rawValue)", withExtension: "jpg") != nil)
            }
        }
    }
}
