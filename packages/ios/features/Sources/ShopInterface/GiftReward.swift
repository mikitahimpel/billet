import Wire

/// The free gift for the day: coins, or an item the couple doesn't own yet.
public enum GiftReward: Hashable, Sendable {
  case coins(Int)
  case item(String)

  public init(_ reward: Wire.GiftReward) {
    switch reward {
    case .coins(let coins): self = .coins(coins)
    case .item(let item): self = .item(item.rawValue)
    }
  }
}

/// What opening the day's gift came to.
public enum GiftOutcome: Hashable, Sendable {
  case opened(GiftReward)
  /// The day's gift was open already, by the partner or an earlier try.
  case taken
}
