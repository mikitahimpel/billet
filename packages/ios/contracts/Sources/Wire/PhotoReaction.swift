/// Wire form of the contracts `Reaction`: what a partner can answer a photo with. The app owns
/// the emoji; the wire carries only the id.
public enum PhotoReaction: String, Codable, Hashable, Sendable, CaseIterable {
  case heart
  case laugh
  case wow
  case sad
  case fire
}

/// One partner's reaction to one note, at its latest. `reaction` is `nil` once they took it back;
/// `rev` orders every change in the room and is what a reconnect resumes from.
public struct NoteReaction: Codable, Hashable, Sendable {
  public let rev: Int
  public let note: NoteId
  public let by: UserId
  public let at: Int
  public let reaction: PhotoReaction?

  public init(rev: Int, note: NoteId, by: UserId, at: Int, reaction: PhotoReaction?) {
    self.rev = rev
    self.note = note
    self.by = by
    self.at = at
    self.reaction = reaction
  }

  private enum CodingKeys: String, CodingKey {
    case rev, note, by, at, reaction
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    rev = try container.decode(Int.self, forKey: .rev)
    note = try container.decode(NoteId.self, forKey: .note)
    by = try container.decode(UserId.self, forKey: .by)
    at = try container.decode(Int.self, forKey: .at)
    reaction = try container.decodeOptionalKey(PhotoReaction.self, forKey: .reaction)
  }
}

/// Sets the caller's reaction to the partner's photo, or takes it back when `reaction` is `nil`.
public struct ReactRequest: Codable, Hashable, Sendable {
  public let note: NoteId
  public let reaction: PhotoReaction?

  public init(note: NoteId, reaction: PhotoReaction?) {
    self.note = note
    self.reaction = reaction
  }

  private enum CodingKeys: String, CodingKey {
    case note, reaction
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    note = try container.decode(NoteId.self, forKey: .note)
    reaction = try container.decodeOptionalKey(PhotoReaction.self, forKey: .reaction)
  }
}

public struct ReactResponse: Codable, Hashable, Sendable {
  public let reaction: NoteReaction

  public init(reaction: NoteReaction) {
    self.reaction = reaction
  }
}

/// Oldest first. The next page starts after the last one's `rev`.
public struct ListReactionsResponse: Codable, Hashable, Sendable {
  public let reactions: [NoteReaction]

  public init(reactions: [NoteReaction]) {
    self.reactions = reactions
  }
}
