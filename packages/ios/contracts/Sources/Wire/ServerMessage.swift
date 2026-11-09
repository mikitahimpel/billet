/// A frame the room sends this device. `seq` supports reconnect. The live stroke frames are the
/// partner's, relayed as they arrive and never stored or replayed.
public enum ServerMessage: Codable, Hashable, Sendable {
  case stroke(seq: Int, stroke: Stroke)
  case presence(PartnerPresence)
  case noteReceived(seq: Int, note: Note)
  case strokeBegin(LiveStrokeStart)
  /// `relayedAt`: the room's clock in ms when the frame reached it.
  case strokePoints(id: Int, points: [Point], relayedAt: Int? = nil)
  case strokeEnd(id: Int)
  /// The partner's device left with this stroke open: discard it, it will not end.
  case strokeDropped(id: Int)
  case clear
  /// Sent to a socket that resumed with `lastCatSeq`.
  case catEntryAdded(CatEntry)
  case catSaved(CatProfile)
  /// Sent to a socket that resumed with `activity: true`.
  case activityUnread(unread: Int)
  /// Sent to a socket that resumed with `lastReactionRev`.
  case reactionChanged(NoteReaction)
  /// Sent to a socket that resumed with `shop: true`, and after each change.
  case shopChanged(ShopResponse)
  /// Sent to a socket that resumed with `lists: true`, and after each change.
  case listsChanged([SharedList])
  /// Sent to a socket that resumed with `moods: true`: each held check-in, then every new one.
  case moodChanged(PartnerCheckIn)
  /// Both swiped ♥ on one card; sent to a socket that resumed with `lists: true`, swiper too.
  case matchFound(PickMatch)
  /// `answered` is how many the partner has now, never which option. `round` is `YYYY-MM-DD`.
  /// Sent to a socket that resumed with `guess: true`.
  case guessProgress(round: String, answered: Int)
  /// Every question opened in round order, and the score as this user sees it. Sent to every
  /// socket that resumed with `guess: true`.
  case guessRevealed(round: String, reveal: [GuessReveal], score: GuessScore)
  /// Sent to a socket that resumed with `riddle: true`: each open riddle, then every change.
  case riddleChanged(Riddle)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case seq
    case stroke
    case state
    case note
    case id
    case points
    case relayedAt
    case entry
    case cat
    case unread
    case reaction
    case shop
    case lists
    case checkIn
    case match
    case round
    case answered
    case reveal
    case score
    case riddle
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Stroke":
      self = .stroke(
        seq: try container.decode(Int.self, forKey: .seq),
        stroke: try container.decode(Stroke.self, forKey: .stroke))
    case "Presence":
      self = .presence(try container.decode(PartnerPresence.self, forKey: .state))
    case "NoteReceived":
      self = .noteReceived(
        seq: try container.decode(Int.self, forKey: .seq),
        note: try container.decode(Note.self, forKey: .note))
    case "StrokeBegin":
      self = .strokeBegin(try LiveStrokeStart(from: decoder))
    case "StrokePoints":
      self = .strokePoints(
        id: try container.decode(Int.self, forKey: .id),
        points: try LiveStrokeStart.decodePoints(container, forKey: .points),
        relayedAt: try container.decodeIfPresent(Int.self, forKey: .relayedAt))
    case "StrokeEnd":
      self = .strokeEnd(id: try container.decode(Int.self, forKey: .id))
    case "StrokeDropped":
      self = .strokeDropped(id: try container.decode(Int.self, forKey: .id))
    case "Clear":
      self = .clear
    case "CatEntryAdded":
      self = .catEntryAdded(try container.decode(CatEntry.self, forKey: .entry))
    case "CatSaved":
      self = .catSaved(try container.decode(CatProfile.self, forKey: .cat))
    case "ActivityUnread":
      self = .activityUnread(unread: try container.decode(Int.self, forKey: .unread))
    case "ReactionChanged":
      self = .reactionChanged(try container.decode(NoteReaction.self, forKey: .reaction))
    case "ShopChanged":
      self = .shopChanged(try container.decode(ShopResponse.self, forKey: .shop))
    case "ListsChanged":
      self = .listsChanged(try container.decode([SharedList].self, forKey: .lists))
    case "MoodChanged":
      self = .moodChanged(try container.decode(PartnerCheckIn.self, forKey: .checkIn))
    case "MatchFound":
      self = .matchFound(try container.decode(PickMatch.self, forKey: .match))
    case "GuessProgress":
      self = .guessProgress(
        round: try container.decode(String.self, forKey: .round),
        answered: try container.decode(Int.self, forKey: .answered))
    case "RiddleChanged":
      self = .riddleChanged(try container.decode(Riddle.self, forKey: .riddle))
    case "GuessRevealed":
      self = .guessRevealed(
        round: try container.decode(String.self, forKey: .round),
        reveal: try container.decode([GuessReveal].self, forKey: .reveal),
        score: try container.decode(GuessScore.self, forKey: .score))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .stroke(let seq, let stroke):
      try container.encode("Stroke", forKey: .tag)
      try container.encode(seq, forKey: .seq)
      try container.encode(stroke, forKey: .stroke)
    case .presence(let state):
      try container.encode("Presence", forKey: .tag)
      try container.encode(state, forKey: .state)
    case .noteReceived(let seq, let note):
      try container.encode("NoteReceived", forKey: .tag)
      try container.encode(seq, forKey: .seq)
      try container.encode(note, forKey: .note)
    case .strokeBegin(let start):
      try container.encode("StrokeBegin", forKey: .tag)
      try start.encode(to: encoder)
    case .strokePoints(let id, let points, let relayedAt):
      try container.encode("StrokePoints", forKey: .tag)
      try container.encode(id, forKey: .id)
      try container.encode(points, forKey: .points)
      try container.encodeIfPresent(relayedAt, forKey: .relayedAt)
    case .strokeEnd(let id):
      try container.encode("StrokeEnd", forKey: .tag)
      try container.encode(id, forKey: .id)
    case .strokeDropped(let id):
      try container.encode("StrokeDropped", forKey: .tag)
      try container.encode(id, forKey: .id)
    case .clear:
      try container.encode("Clear", forKey: .tag)
    case .catEntryAdded(let entry):
      try container.encode("CatEntryAdded", forKey: .tag)
      try container.encode(entry, forKey: .entry)
    case .catSaved(let cat):
      try container.encode("CatSaved", forKey: .tag)
      try container.encode(cat, forKey: .cat)
    case .activityUnread(let unread):
      try container.encode("ActivityUnread", forKey: .tag)
      try container.encode(unread, forKey: .unread)
    case .reactionChanged(let reaction):
      try container.encode("ReactionChanged", forKey: .tag)
      try container.encode(reaction, forKey: .reaction)
    case .shopChanged(let shop):
      try container.encode("ShopChanged", forKey: .tag)
      try container.encode(shop, forKey: .shop)
    case .listsChanged(let lists):
      try container.encode("ListsChanged", forKey: .tag)
      try container.encode(lists, forKey: .lists)
    case .moodChanged(let checkIn):
      try container.encode("MoodChanged", forKey: .tag)
      try container.encode(checkIn, forKey: .checkIn)
    case .matchFound(let match):
      try container.encode("MatchFound", forKey: .tag)
      try container.encode(match, forKey: .match)
    case .guessProgress(let round, let answered):
      try container.encode("GuessProgress", forKey: .tag)
      try container.encode(round, forKey: .round)
      try container.encode(answered, forKey: .answered)
    case .guessRevealed(let round, let reveal, let score):
      try container.encode("GuessRevealed", forKey: .tag)
      try container.encode(round, forKey: .round)
      try container.encode(reveal, forKey: .reveal)
      try container.encode(score, forKey: .score)
    case .riddleChanged(let riddle):
      try container.encode("RiddleChanged", forKey: .tag)
      try container.encode(riddle, forKey: .riddle)
    }
  }
}
