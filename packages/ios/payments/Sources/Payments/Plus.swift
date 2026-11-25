import Foundation

/// Ourio Plus as the store sells it. Must match `@billet/contracts-domain/plus` and
/// `apps/ios/Ourio.storekit`; `coin-packs-sync.test.ts` fails when they disagree.
public struct PlusCatalog: Hashable, Sendable {
  public enum Plan: String, Codable, Hashable, Sendable, CaseIterable {
    case monthly
    case yearly
  }

  public struct Definition: Codable, Hashable, Sendable {
    public let id: String
    public let plan: Plan
    /// US dollars, such as `"3.99"`. The store shows its own.
    public let price: String
    public let displayName: String
    public let description: String
  }

  private struct File: Codable {
    struct Section: Codable {
      let group: String
      let parcelPriceCeiling: Int
      let plans: [Definition]
    }
    let plus: Section
  }

  public let group: String
  /// The dearest a piece a parcel may hold, in coins, inclusive; the server holds the same.
  public let parcelPriceCeiling: Int
  /// Monthly first: it is the smaller promise.
  public let plans: [Definition]

  public init(group: String, parcelPriceCeiling: Int, plans: [Definition]) {
    self.group = group
    self.parcelPriceCeiling = parcelPriceCeiling
    self.plans = plans
  }

  public init(json: Data) throws {
    let section = try JSONDecoder().decode(File.self, from: json).plus
    self.init(
      group: section.group, parcelPriceCeiling: section.parcelPriceCeiling, plans: section.plans)
  }

  public static let standard: PlusCatalog = {
    guard let url = Bundle.module.url(forResource: "coin-packs", withExtension: "json"),
      let data = try? Data(contentsOf: url), let catalog = try? PlusCatalog(json: data)
    else { preconditionFailure("coin-packs.json has no Plus section") }
    return catalog
  }()

  public var productIDs: [String] { plans.map(\.id) }

  public func definition(_ productID: String) -> Definition? {
    plans.first { $0.id == productID }
  }

  /// For builds that show no store price.
  public func offer(_ definition: Definition) -> PlusOffer {
    PlusOffer(
      id: definition.id, plan: definition.plan, displayName: definition.displayName,
      displayPrice: "$\(definition.price)")
  }
}

/// One Plus plan as the store prices it for this buyer.
public struct PlusOffer: Hashable, Sendable, Identifiable {
  /// The App Store product ID.
  public let id: String
  public let plan: PlusCatalog.Plan
  public let displayName: String
  /// Already in the buyer's currency.
  public let displayPrice: String

  public init(id: String, plan: PlusCatalog.Plan, displayName: String, displayPrice: String) {
    self.id = id
    self.plan = plan
    self.displayName = displayName
    self.displayPrice = displayPrice
  }
}

public enum SubscribeResult: Hashable, Sendable {
  /// The store took it and the server gave it to the pair.
  case subscribed
  case cancelled
  /// Ask to Buy: it comes later, through ``Payments/updates()``.
  case pending
  /// The store took it but the server hasn't heard yet. The transaction stays unfinished and is
  /// sent again; ``PaymentsUpdate/plusChanged`` says when it lands.
  case awaitingServer
}
