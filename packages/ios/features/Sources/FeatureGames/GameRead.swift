/// A game's state read from the pair's room. `last` counts the reads sent, so a late answer to an
/// earlier one doesn't end the one still out.
public enum GameRead: Equatable, Sendable {
  case idle(last: Int)
  case reading(request: Int)

  public var isReading: Bool {
    switch self {
    case .idle: false
    case .reading: true
    }
  }

  /// The read to send next, or nil while one is out.
  func next() -> (GameRead, Int)? {
    switch self {
    case .idle(let last): (.reading(request: last + 1), last + 1)
    case .reading: nil
    }
  }

  func answered(_ request: Int) -> GameRead {
    if case .reading(let out) = self, out == request { .idle(last: request) } else { self }
  }
}
