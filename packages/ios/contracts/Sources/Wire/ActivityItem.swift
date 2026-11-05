/// Who did it, as the caller sees it: themselves, their partner, the cat on its own, or the App
/// Store (a refund names no user).
public enum ActivityActor: String, Codable, Hashable, Sendable {
  case me = "Me"
  case partner = "Partner"
  case cat = "Cat"
  case store = "Store"
}

/// Where tapping an Inbox item goes.
public enum ActivityTarget: Codable, Hashable, Sendable {
  /// A text note.
  case note(NoteId)
  /// A drawing or a photo, in Moments.
  case moments(NoteId)
  case cat
  /// A plant's card, such as `monstera`.
  case plant(String)
  /// A shop item, such as `armchair`.
  case shopItem(String)
  /// A shop offer with several items, such as `bundle:starter-ink`.
  case shopOffer(String)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case note
    case plant
    case id
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Note":
      self = .note(try container.decode(NoteId.self, forKey: .note))
    case "Moments":
      self = .moments(try container.decode(NoteId.self, forKey: .note))
    case "Cat":
      self = .cat
    case "Plant":
      self = .plant(try container.decode(String.self, forKey: .plant))
    case "ShopItem":
      self = .shopItem(try container.decode(String.self, forKey: .id))
    case "ShopOffer":
      self = .shopOffer(try container.decode(String.self, forKey: .id))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .note(let note):
      try container.encode("Note", forKey: .tag)
      try container.encode(note, forKey: .note)
    case .moments(let note):
      try container.encode("Moments", forKey: .tag)
      try container.encode(note, forKey: .note)
    case .cat:
      try container.encode("Cat", forKey: .tag)
    case .plant(let plant):
      try container.encode("Plant", forKey: .tag)
      try container.encode(plant, forKey: .plant)
    case .shopItem(let id):
      try container.encode("ShopItem", forKey: .tag)
      try container.encode(id, forKey: .id)
    case .shopOffer(let id):
      try container.encode("ShopOffer", forKey: .tag)
      try container.encode(id, forKey: .id)
    }
  }
}

/// One Inbox item. `id` is its source's own, such as `cat:<entry id>` or `note:<note id>`, so the
/// same item never shows twice; `at` is the server's time in epoch milliseconds. `cursor` is its
/// opaque place in the list: send it back as `upTo` to mark it read, never build one.
public struct ActivityItem: Codable, Hashable, Sendable {
  public let id: String
  public let at: Int
  public let actor: ActivityActor
  public let event: ActivityEvent
  public let target: ActivityTarget?
  public let cursor: String

  public init(
    id: String, at: Int, actor: ActivityActor, event: ActivityEvent,
    target: ActivityTarget? = nil, cursor: String
  ) {
    self.id = id
    self.at = at
    self.actor = actor
    self.event = event
    self.target = target
    self.cursor = cursor
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case at
    case actor
    case event
    case target
    case cursor
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    at = try container.decode(Int.self, forKey: .at)
    actor = try container.decode(ActivityActor.self, forKey: .actor)
    event = try container.decode(ActivityEvent.self, forKey: .event)
    target = try container.decodeOptionalKey(ActivityTarget.self, forKey: .target)
    cursor = try container.decode(String.self, forKey: .cursor)
  }
}
