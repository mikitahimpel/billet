/// A pack of stamps sold for money, as the shop shows it. The shop never talks to the App Store:
/// a ``StampPackSource`` does, and credits the wallet itself.
public struct StampPackOffer: Identifiable, Hashable, Sendable {
  public let id: String
  public let stamps: Int
  public let displayName: String
  /// The price in the buyer's currency, already formatted by the store.
  public let displayPrice: String

  public init(id: String, stamps: Int, displayName: String, displayPrice: String) {
    self.id = id
    self.stamps = stamps
    self.displayName = displayName
    self.displayPrice = displayPrice
  }
}

/// Where a purchase of stamps stands.
public enum StampPackState: Hashable, Sendable {
  case idle
  case buying
  /// Waiting for someone to approve it, such as Ask to Buy.
  case pending
  case failed(String)
}

/// What sells stamp packs to the shop's row of them. Kept apart from StoreKit so the shop only
/// draws what this says.
@MainActor
public protocol StampPackSource: AnyObject {
  /// The packs for sale; empty while there are none, or none yet.
  var packs: [StampPackOffer] { get }
  var state: StampPackState { get }
  func buy(_ pack: StampPackOffer)
}

/// No packs for sale: stamps are given, not sold, for now. The row shows as a placeholder.
@MainActor
public final class NoStampPacks: StampPackSource {
  public let packs: [StampPackOffer] = []
  public let state = StampPackState.idle

  public init() {}

  public func buy(_ pack: StampPackOffer) {}
}
