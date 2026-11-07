/// A draw-guess riddle's id: a UUID the drawer makes once and repeats on every retry of the send.
public typealias RiddleId = IdempotencyKey

/// How a riddle's round stands. `at` is epoch milliseconds.
public enum RiddleState: Codable, Hashable, Sendable {
  case open
  case solved(at: Int)
  case givenUp(at: Int)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case at
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Open": self = .open
    case "Solved": self = .solved(at: try container.decode(Int.self, forKey: .at))
    case "GivenUp": self = .givenUp(at: try container.decode(Int.self, forKey: .at))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .open:
      try container.encode("Open", forKey: .tag)
    case .solved(let at):
      try container.encode("Solved", forKey: .tag)
      try container.encode(at, forKey: .at)
    case .givenUp(let at):
      try container.encode("GivenUp", forKey: .tag)
      try container.encode(at, forKey: .at)
    }
  }
}

/// A letter Mochi's hint opened. `index` counts the word's letters from 0, spaces not counted;
/// `letter` is one of a to z.
public struct RevealedLetter: Codable, Hashable, Sendable {
  public let index: Int
  public let letter: String

  public init(index: Int, letter: String) {
    self.index = index
    self.letter = letter
  }
}

/// One riddle as this user sees it. `shape` is the letters of each word ("north pole" is
/// `[5, 4]`). `tiles` are shuffled single letters, 12 unless a word of 11 or 12 letters needs its
/// two decoys; `removed` are the indexes of the tiles the first hint took away. `word` is set for
/// the drawer, and for both once the round has ended: the guesser never has it while it is open.
public struct Riddle: Codable, Hashable, Sendable {
  public let id: RiddleId
  public let drawer: UserId
  public let shape: [Int]
  public let tiles: [String]
  public let revealed: [RevealedLetter]
  public let removed: [Int]
  public let hints: Int
  public let tries: Int
  public let state: RiddleState
  public let word: String?
  public let compact: CompactStrokes
  public let image: MediaKey
  /// When it was sent, epoch milliseconds.
  public let at: Int

  public init(
    id: RiddleId, drawer: UserId, shape: [Int], tiles: [String], revealed: [RevealedLetter] = [],
    removed: [Int] = [], hints: Int = 0, tries: Int = 0, state: RiddleState = .open,
    word: String? = nil, compact: CompactStrokes, image: MediaKey, at: Int
  ) {
    self.id = id
    self.drawer = drawer
    self.shape = shape
    self.tiles = tiles
    self.revealed = revealed
    self.removed = removed
    self.hints = hints
    self.tries = tries
    self.state = state
    self.word = word
    self.compact = compact
    self.image = image
    self.at = at
  }

  private enum CodingKeys: String, CodingKey {
    case id, drawer, shape, tiles, revealed, removed, hints, tries, state, word, compact, image, at
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(RiddleId.self, forKey: .id)
    drawer = try container.decode(UserId.self, forKey: .drawer)
    shape = try container.decode([Int].self, forKey: .shape)
    tiles = try container.decode([String].self, forKey: .tiles)
    revealed = try container.decode([RevealedLetter].self, forKey: .revealed)
    removed = try container.decode([Int].self, forKey: .removed)
    hints = try container.decode(Int.self, forKey: .hints)
    tries = try container.decode(Int.self, forKey: .tries)
    state = try container.decode(RiddleState.self, forKey: .state)
    word = try container.decodeOptionalKey(String.self, forKey: .word)
    compact = try container.decode(CompactStrokes.self, forKey: .compact)
    image = try container.decode(MediaKey.self, forKey: .image)
    at = try container.decode(Int.self, forKey: .at)
  }
}

/// `GET /v1/riddles`: `open` holds at most one riddle per member; `ended` the last 20 that ended,
/// newest first, for the board. `series` counts solves in a row since the last give-up; `best`
/// is the longest it has been.
public struct RiddlesResponse: Codable, Hashable, Sendable {
  public let open: [Riddle]
  public let ended: [Riddle]
  public let series: Int
  public let best: Int

  public init(open: [Riddle] = [], ended: [Riddle] = [], series: Int = 0, best: Int = 0) {
    self.open = open
    self.ended = ended
    self.series = series
    self.best = best
  }
}

/// `POST /v1/riddles`. `image` is the PNG uploaded through `POST /v1/media` first. `word` is
/// trimmed and lowercased by the server, then must be lowercase a to z, single-spaced, at most 24
/// characters and 12 letters, or the answer is `.api(.invalidRequest)` with status 400. A second
/// riddle while this user's last one is open is 409; the same `id` again answers with the first.
public struct SendRiddleRequest: Codable, Hashable, Sendable {
  public let id: RiddleId
  public let word: String
  public let compact: CompactStrokes
  public let image: MediaKey

  public init(id: RiddleId, word: String, compact: CompactStrokes, image: MediaKey) {
    self.id = id
    self.word = word
    self.compact = compact
    self.image = image
  }
}

/// `POST /v1/riddles/:id/guess`: one try. `key` is this try's own: a retry with it answers with
/// the first try's result and counts nothing more.
public struct GuessRiddleRequest: Codable, Hashable, Sendable {
  public let key: IdempotencyKey
  public let guess: String

  public init(key: IdempotencyKey, guess: String) {
    self.key = key
    self.guess = guess
  }
}

/// The riddle after a try, and whether the try was the word.
public struct GuessRiddleResponse: Codable, Hashable, Sendable {
  public let riddle: Riddle
  public let right: Bool

  public init(riddle: Riddle, right: Bool) {
    self.riddle = riddle
    self.right = right
  }
}
