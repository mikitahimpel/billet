import BilletKit
import ShopInterface

/// A stamp or seal picked for a note: an owned one is chosen at once; a locked one asks first, then buys. Short of
/// coins the Coins sheet takes over; a buy the Shop didn't place leaves the note as it was.
public nonisolated enum PostageUnlockMachine: Machine {
  public enum State: Equatable, Sendable {
    case idle
    /// The confirm sheet is up for it.
    case confirming(NotePostage)
    /// Asked the Shop to buy it; its answer comes back as `bought`, `coinsShort` or `refused`.
    case buying(NotePostage)
  }

  public enum Event: Equatable, Sendable {
    case tapped(NotePostage, owned: Bool)
    case buyTapped
    case cancelled
    case bought
    case coinsShort
    case refused
  }

  public enum Output: Equatable, Sendable {
    case select(NotePostage)
    case buy(NotePostage)
    case openCoins
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.idle, .tapped(let postage, let owned)):
      owned ? (.idle, [.select(postage)]) : (.confirming(postage), [])
    case (.confirming(let postage), .buyTapped): (.buying(postage), [.buy(postage)])
    case (.confirming, .cancelled): (.idle, [])
    case (.buying(let postage), .bought): (.idle, [.select(postage)])
    case (.buying, .coinsShort): (.idle, [.openCoins])
    case (.buying, .refused): (.idle, [])
    case (.idle, .buyTapped), (.idle, .cancelled), (.idle, .bought), (.idle, .coinsShort),
      (.idle, .refused),
      (.confirming, .tapped), (.confirming, .bought), (.confirming, .coinsShort),
      (.confirming, .refused),
      (.buying, .tapped), (.buying, .buyTapped), (.buying, .cancelled):
      (state, [])
    }
  }
}
