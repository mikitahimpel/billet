import Foundation

/// The stamp packs this build knows: product ID, stamps and the reference price. One list for the
/// app, the server (`@billet/contracts-domain/stamp-packs`) and `apps/ios/App/Billet.storekit`; a
/// test on each side fails when they disagree.
public struct StampPackCatalog: Hashable, Sendable {
  public struct Definition: Codable, Hashable, Sendable {
    public let id: String
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
    guard let url = Bundle.module.url(forResource: "stamp-packs", withExtension: "json"),
      let data = try? Data(contentsOf: url), let catalog = try? StampPackCatalog(json: data)
    else { preconditionFailure("stamp-packs.json is missing from the Payments bundle") }
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
