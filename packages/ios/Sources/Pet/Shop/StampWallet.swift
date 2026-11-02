/// Tunable values of the shop.
public enum ShopConfig {
  /// Stamps every demo or test account is granted once, until stamps can be bought.
  public static let demoGrant = 10_000
}

/// The pair's stamps, kept as a ledger: the balance is the sum of its entries, and each entry has
/// a source and an ID that appears only once. A grant or purchase that arrives again under the
/// same ID changes nothing.
public struct StampWallet: Codable, Hashable, Sendable {
  public enum Source: String, Codable, Hashable, Sendable {
    /// Free stamps given by the app.
    case grant
    /// Stamps bought for money. Nothing creates these yet.
    case purchase
    /// Stamps paid for an item.
    case spend
  }

  /// A way stamps can arrive. Spending is not one: it only comes from ``debit(_:id:)``.
  public enum Credit: Hashable, Sendable {
    case grant
    case purchase

    var source: Source {
      switch self {
      case .grant: .grant
      case .purchase: .purchase
      }
    }
  }

  public struct Entry: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let source: Source
    /// Positive for stamps in, negative for stamps out.
    public let amount: Int
  }

  public private(set) var entries: [Entry]
  private var seen: Set<String>

  public init() {
    entries = []
    seen = []
  }

  public var balance: Int { entries.reduce(0) { $0 + $1.amount } }

  public func hasEntry(_ id: String) -> Bool { seen.contains(id) }

  /// Adds stamps under a unique `id`.
  public mutating func credit(_ amount: Int, as credit: Credit, id: String) -> ShopOutcome {
    guard amount > 0, seen.insert(id).inserted else { return .duplicate }
    entries.append(Entry(id: id, source: credit.source, amount: amount))
    return .applied
  }

  /// Takes `amount` under a unique `id`, or leaves the ledger alone and throws when the balance
  /// would not cover it.
  public mutating func debit(_ amount: Int, id: String) throws(ShopError) -> ShopOutcome {
    guard !seen.contains(id) else { return .duplicate }
    guard amount <= balance else { throw .notEnoughStamps(needed: amount, have: balance) }
    seen.insert(id)
    entries.append(Entry(id: id, source: .spend, amount: -amount))
    return .applied
  }
}

public enum ShopError: Error, Hashable, Sendable {
  case unknownItem
  case notEnoughStamps(needed: Int, have: Int)
  /// A material is bought once.
  case alreadyOwned
  case notInCloset
  /// The item cannot be used this way, such as placing a treat.
  case wrongKind
  case roomIsFull
  case unknownPlacement
}

/// Whether a change took effect now or had already been applied under the same transaction ID.
public enum ShopOutcome: Hashable, Sendable {
  case applied
  case duplicate
}
