/// Custom data carried by a push, not the whole APNs envelope.
/// `compact` is absent for photos, which have no vector rendition.
public enum PushPayload: Codable, Hashable, Sendable {
  case widget(noteId: NoteId, author: UserId, compact: CompactStrokes?)
  case alert(noteId: NoteId, author: UserId, compact: CompactStrokes?)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case noteId
    case author
    case compact
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    let noteId = try container.decode(NoteId.self, forKey: .noteId)
    let author = try container.decode(UserId.self, forKey: .author)
    let compact = try container.decodeIfPresent(CompactStrokes.self, forKey: .compact)
    switch tag {
    case "Widget": self = .widget(noteId: noteId, author: author, compact: compact)
    case "Alert": self = .alert(noteId: noteId, author: author, compact: compact)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .widget(let noteId, let author, let compact):
      try container.encode("Widget", forKey: .tag)
      try container.encode(noteId, forKey: .noteId)
      try container.encode(author, forKey: .author)
      try container.encodeIfPresent(compact, forKey: .compact)
    case .alert(let noteId, let author, let compact):
      try container.encode("Alert", forKey: .tag)
      try container.encode(noteId, forKey: .noteId)
      try container.encode(author, forKey: .author)
      try container.encodeIfPresent(compact, forKey: .compact)
    }
  }
}
