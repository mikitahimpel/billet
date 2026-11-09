public enum ClientMessage: Codable, Hashable, Sendable {
  /// Each flag or cursor asks for its frames now and on every change; left out, none. Notes come
  /// after `lastSeq`, cat entries after `lastCatSeq`, reactions after `lastReactionRev`;
  /// `guess` asks for `guessProgress` and `guessRevealed`.
  case resume(
    lastSeq: Int, lastCatSeq: Int? = nil, activity: Bool? = nil, lastReactionRev: Int? = nil,
    shop: Bool? = nil, lists: Bool? = nil, moods: Bool? = nil, guess: Bool? = nil,
    riddle: Bool? = nil, streak: Bool? = nil)
  /// From a client that does not stream.
  case stroke(Stroke)
  case presence(PresenceState)
  /// Its points follow in `strokePoints`.
  case strokeBegin(LiveStrokeStart)
  /// At most ``LiveStrokeStart/maxPoints``.
  case strokePoints(id: Int, points: [Point])
  case strokeEnd(id: Int)
  case clear

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case lastSeq
    case lastCatSeq
    case activity
    case lastReactionRev
    case shop
    case lists
    case moods
    case guess
    case riddle
    case streak
    case stroke
    case state
    case id
    case color
    case width
    case points
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Resume":
      self = .resume(
        lastSeq: try container.decode(Int.self, forKey: .lastSeq),
        lastCatSeq: try container.decodeOptionalKey(Int.self, forKey: .lastCatSeq),
        activity: try container.decodeOptionalKey(Bool.self, forKey: .activity),
        lastReactionRev: try container.decodeOptionalKey(Int.self, forKey: .lastReactionRev),
        shop: try container.decodeOptionalKey(Bool.self, forKey: .shop),
        lists: try container.decodeOptionalKey(Bool.self, forKey: .lists),
        moods: try container.decodeOptionalKey(Bool.self, forKey: .moods),
        guess: try container.decodeOptionalKey(Bool.self, forKey: .guess),
        riddle: try container.decodeOptionalKey(Bool.self, forKey: .riddle),
        streak: try container.decodeOptionalKey(Bool.self, forKey: .streak))
    case "Stroke":
      self = .stroke(try container.decode(Stroke.self, forKey: .stroke))
    case "Presence":
      self = .presence(try container.decode(PresenceState.self, forKey: .state))
    case "StrokeBegin":
      self = .strokeBegin(try LiveStrokeStart(from: decoder))
    case "StrokePoints":
      self = .strokePoints(
        id: try container.decode(Int.self, forKey: .id),
        points: try LiveStrokeStart.decodePoints(container, forKey: .points))
    case "StrokeEnd":
      self = .strokeEnd(id: try container.decode(Int.self, forKey: .id))
    case "Clear":
      self = .clear
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .resume(
      let lastSeq, let lastCatSeq, let activity, let lastReactionRev, let shop, let lists,
      let moods, let guess, let riddle, let streak
    ):
      try container.encode("Resume", forKey: .tag)
      try container.encode(lastSeq, forKey: .lastSeq)
      try container.encodeIfPresent(lastCatSeq, forKey: .lastCatSeq)
      try container.encodeIfPresent(activity, forKey: .activity)
      try container.encodeIfPresent(lastReactionRev, forKey: .lastReactionRev)
      try container.encodeIfPresent(shop, forKey: .shop)
      try container.encodeIfPresent(lists, forKey: .lists)
      try container.encodeIfPresent(moods, forKey: .moods)
      try container.encodeIfPresent(guess, forKey: .guess)
      try container.encodeIfPresent(riddle, forKey: .riddle)
      try container.encodeIfPresent(streak, forKey: .streak)
    case .stroke(let stroke):
      try container.encode("Stroke", forKey: .tag)
      try container.encode(stroke, forKey: .stroke)
    case .presence(let state):
      try container.encode("Presence", forKey: .tag)
      try container.encode(state, forKey: .state)
    case .strokeBegin(let start):
      try container.encode("StrokeBegin", forKey: .tag)
      try start.encode(to: encoder)
    case .strokePoints(let id, let points):
      try container.encode("StrokePoints", forKey: .tag)
      try container.encode(id, forKey: .id)
      try container.encode(points, forKey: .points)
    case .strokeEnd(let id):
      try container.encode("StrokeEnd", forKey: .tag)
      try container.encode(id, forKey: .id)
    case .clear:
      try container.encode("Clear", forKey: .tag)
    }
  }
}
