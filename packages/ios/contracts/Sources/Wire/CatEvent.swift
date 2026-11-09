/// `noteShared` is written by the room when a note is stored, never sent by a phone; `kind` is
/// the note's `_tag`.
public enum CatEvent: Codable, Hashable, Sendable {
  /// 1 to 500 grams.
  case fed(grams: Int)
  case petted
  case played
  /// The plant by the window; it fills no need.
  case watered
  case noteShared(note: NoteId, kind: String)
  /// `game` matches `[a-z0-9-]{1,32}`, such as `laser`.
  case gamePlayed(game: String, score: Int, won: Bool)
  case slept
  case shooed

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case grams
    case note
    case kind
    case game
    case score
    case won
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Fed":
      self = .fed(grams: try container.decode(Int.self, forKey: .grams))
    case "Petted":
      self = .petted
    case "Played":
      self = .played
    case "Watered":
      self = .watered
    case "NoteShared":
      self = .noteShared(
        note: try container.decode(NoteId.self, forKey: .note),
        kind: try container.decode(String.self, forKey: .kind))
    case "GamePlayed":
      self = .gamePlayed(
        game: try container.decode(String.self, forKey: .game),
        score: try container.decode(Int.self, forKey: .score),
        won: try container.decode(Bool.self, forKey: .won))
    case "Slept":
      self = .slept
    case "Shooed":
      self = .shooed
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .fed(let grams):
      try container.encode("Fed", forKey: .tag)
      try container.encode(grams, forKey: .grams)
    case .petted:
      try container.encode("Petted", forKey: .tag)
    case .played:
      try container.encode("Played", forKey: .tag)
    case .watered:
      try container.encode("Watered", forKey: .tag)
    case .noteShared(let note, let kind):
      try container.encode("NoteShared", forKey: .tag)
      try container.encode(note, forKey: .note)
      try container.encode(kind, forKey: .kind)
    case .gamePlayed(let game, let score, let won):
      try container.encode("GamePlayed", forKey: .tag)
      try container.encode(game, forKey: .game)
      try container.encode(score, forKey: .score)
      try container.encode(won, forKey: .won)
    case .slept:
      try container.encode("Slept", forKey: .tag)
    case .shooed:
      try container.encode("Shooed", forKey: .tag)
    }
  }
}
