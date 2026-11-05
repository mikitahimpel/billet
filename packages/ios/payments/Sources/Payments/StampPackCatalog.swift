import Foundation

/// The stamp packs this build knows: product ID, stamps and the reference price. One list for the
/// app, the server (`@billet/contracts-domain/coin-packs`) and `apps/ios/App/Billet.storekit`; a
/// test on each side fails when they disagree.
public struct StampPackCatalog: Hashable, Sendable {
  public struct Definition: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
      case id, price, displayName, description
      case stamps = "coins"
    }

    public let id: String
    /// The coins the pack credits (`coins` in coin-packs.json).
    public let stamps: Int
    /// The reference price in US dollars, such as `"0.99"`. The store shows its own.
    public let price: String
    public let displayName: String
    public let description: String
  }

  private struct File: Codable {
    let packs: [Definition]
  }

  public let packs: [Definition]

  public init(packs: [Definition]) {
    self.packs = packs
  }

  public init(json: Data) throws {
    packs = try JSONDecoder().decode(File.self, from: json).packs
  }

  /// The list bundled with the app.
  public static let standard: StampPackCatalog = {
    guard let url = Bundle.module.url(forResource: "coin-packs", withExtension: "json"),
      let data = try? Data(contentsOf: url), let catalog = try? StampPackCatalog(json: data)
    else { preconditionFailure("coin-packs.json is missing from the Payments bundle") }
    return catalog
  }()

  public var productIDs: [String] { packs.map(\.id) }

  public func definition(_ productID: String) -> Definition? {
    packs.first { $0.id == productID }
  }

  /// The pack at its reference price, for builds that show no store price.
  public func pack(_ definition: Definition) -> StampPack {
    StampPack(
      id: definition.id, stamps: definition.stamps, displayName: definition.displayName,
      description: definition.description, displayPrice: "$\(definition.price)")
  }
}
