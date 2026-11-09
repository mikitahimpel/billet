import Foundation
import Pet

/// What the choose-your-cat scene shows: a few cats on cushions, each partner's pick marked over
/// its cat, the rings that fill while each holds the agreed cat, and then the adopted cat.
public struct AdoptionSceneState: Equatable, Sendable {
  public enum Moment: Equatable, Sendable {
    /// Choosing: the cats sit on their cushions, the candidates bid while the picks differ.
    case choosing
    /// The cat at `adopted` was chosen: it greets the pair, the others settle down.
    case adopted
    /// The adopted cat walks out of the scene and the camera follows it.
    case leaving
  }

  /// The cats on the cushions, left to right.
  public var cats: [CatChoice]
  /// This phone's pick and the partner's, as places in `cats`.
  public var mine: Int?
  public var theirs: Int?
  /// How full each ring is, from 0 to 1, drawn around the agreed cat.
  public var myRing: Double
  public var theirRing: Double
  public var adopted: Int?
  public var moment: Moment

  public init(
    cats: [CatChoice], mine: Int? = nil, theirs: Int? = nil, myRing: Double = 0,
    theirRing: Double = 0, adopted: Int? = nil, moment: Moment = .choosing
  ) {
    self.cats = cats
    self.mine = mine
    self.theirs = theirs
    self.myRing = myRing
    self.theirRing = theirRing
    self.adopted = adopted
    self.moment = moment
  }

  /// The cat both picked, while choosing.
  public var agreed: Int? {
    guard moment == .choosing, let mine, mine == theirs else { return nil }
    return mine
  }
}

public enum AdoptionSceneEvent: Hashable, Sendable {
  /// A quick tap on the cat at this place.
  case tapped(Int)
  /// A finger went down on the agreed cat and stays there, or came up.
  case pressing(Bool)
  /// The adopted cat has walked out: time to go into the room.
  case left
}
