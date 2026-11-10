import Wire

extension PhotoReaction {
  /// The same emoji the server puts in a reaction's push.
  public var emoji: String {
    switch self {
    case .heart: "❤️"
    case .laugh: "😂"
    case .wow: "😮"
    case .sad: "😢"
    case .fire: "🔥"
    }
  }

  public var label: String {
    switch self {
    case .heart: "Love"
    case .laugh: "Laugh"
    case .wow: "Wow"
    case .sad: "Sad"
    case .fire: "Fire"
    }
  }
}
