/// Why the server did not take a shop request, as the Shop words it.
public enum ShopError: Error, Equatable, Sendable {
  /// The partner spent the coins first; `have` is the balance the server holds.
  case notEnoughCoins(needed: Int, have: Int)
  case alreadyOwned
  /// The day's gift was opened already, on the pair's local `day`.
  case giftTaken(day: String)
  case bonusTaken
  case collectionIncomplete
  /// The network, the server, or a request it would not take. Trying again is safe.
  case unavailable
  case signedOut
}
