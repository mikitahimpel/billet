/// What a partner can do for the cat. Matches the `kind` of a room `play` frame.
public enum PlayKind: String, Hashable, Sendable {
  case pet
  /// The day's shared treat, which the room's streak counts.
  case treat
  /// Any other food, such as a treat from the closet. Only the pet's life counts it.
  case feed
  case play
  /// The cat was put to bed.
  case sleep
  /// The cat was shooed off the desk or the cardigan.
  case shoo

  /// The life event a frame of this kind is, or nil for the day's treat, which feeds the cat
  /// through a separate `feed` frame so the room's streak and the life stay apart.
  public var lifeKind: LifeEvent.Kind? {
    switch self {
    case .pet: .pet
    case .treat: nil
    case .feed: .feed
    case .play: .play
    case .sleep: .sleep
    case .shoo: .shoo
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
    case .shoo: .shoo
    case .note: nil
    }
  }
}
