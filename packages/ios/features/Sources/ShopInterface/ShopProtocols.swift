import Wire

/// The pair's coins, for the header and anything that shows a price next to them.
@MainActor
public protocol CoinsBalanceProviding: AnyObject {
  var coins: Int { get }
  /// True while the coins are the pair's room on the server; false shows the last ones heard.
  var isSynced: Bool { get }
}

/// Asks the server to pay for something the couple did. The event names what it was, so a retry,
/// or the same thing again, is paid once.
@MainActor
public protocol CoinEarning: AnyObject {
  func earn(_ event: EarnEvent)
}

/// A treat for the cat, paid in coins. False when it couldn't be bought; the Coins sheet may be
/// open then.
@MainActor
public protocol TreatBuying: AnyObject {
  func treat() -> Bool
}
