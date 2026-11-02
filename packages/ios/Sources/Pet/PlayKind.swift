/// What a partner can do for the cat. Matches the `kind` of a room `play` frame.
public enum PlayKind: String, Hashable, Sendable {
  case pet
  /// The day's shared treat, which the room's streak counts.
  case treat
  /// Any other food, such as a treat from the closet. Only the pet's life counts it.
  case feed
  /// A game with the cat.
  case play
  /// The cat was put to bed.
  case sleep

  /// The life event a frame of this kind is, or nil for the day's treat, which feeds the cat
  /// through a separate `feed` frame so the room's streak and the life stay apart.
  public var lifeKind: LifeEvent.Kind? {
    switch self {
    case .pet: .pet
    case .treat: nil
    case .feed: .feed
    case .play: .play
    case .sleep: .sleep
    }
  }
}

extension LifeEvent.Kind {
  /// The `play` frame that carries it, or nil for a note, which travels as the note itself.
  public var playKind: PlayKind? {
    switch self {
    case .feed: .feed
    case .pet: .pet
    case .play: .play
    case .sleep: .sleep
    case .note: nil
    }
  }
}
