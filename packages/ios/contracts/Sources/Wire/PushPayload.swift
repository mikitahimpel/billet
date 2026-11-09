/// Custom data of a push, not the whole APNs envelope. `compact` is for drawings only, `text`
/// for text notes only, `paper` when the sender chose one.
public enum PushPayload: Codable, Hashable, Sendable {
  case widget(
    noteId: NoteId, author: UserId, compact: CompactStrokes?, text: NoteText? = nil,
    paper: PaperColor? = nil)
  case alert(
    noteId: NoteId, author: UserId, compact: CompactStrokes?, text: NoteText? = nil,
    paper: PaperColor? = nil)
  /// To a photo's author.
  case reaction(noteId: NoteId, by: UserId, reaction: PhotoReaction)
  /// Always carries the strokes: a Live Activity has no network.
  case liveActivity(
    noteId: NoteId, author: UserId, compact: CompactStrokes, paper: PaperColor? = nil)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case noteId
    case author
    case compact
    case text
    case paper
    case by
    case reaction
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    let noteId = try container.decode(NoteId.self, forKey: .noteId)
    if tag == "Reaction" {
      self = .reaction(
        noteId: noteId, by: try container.decode(UserId.self, forKey: .by),
        reaction: try container.decode(PhotoReaction.self, forKey: .reaction))
      return
    }
    let author = try container.decode(UserId.self, forKey: .author)
    let compact = try container.decodeOptionalKey(CompactStrokes.self, forKey: .compact)
    let text = try container.decodeOptionalKey(NoteText.self, forKey: .text)
    let paper = try container.decodeOptionalKey(PaperColor.self, forKey: .paper)
    switch tag {
    case "Widget":
      self = .widget(noteId: noteId, author: author, compact: compact, text: text, paper: paper)
    case "Alert":
      self = .alert(noteId: noteId, author: author, compact: compact, text: text, paper: paper)
    case "LiveActivity":
      guard let compact else {
        throw DecodingError.keyNotFound(
          CodingKeys.compact,
          .init(
            codingPath: container.codingPath, debugDescription: "a Live Activity needs strokes"))
      }
      self = .liveActivity(noteId: noteId, author: author, compact: compact, paper: paper)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let fields: (NoteId, UserId, CompactStrokes?, NoteText?, PaperColor?)
    switch self {
    case .widget(let noteId, let author, let compact, let text, let paper):
      try container.encode("Widget", forKey: .tag)
      fields = (noteId, author, compact, text, paper)
    case .alert(let noteId, let author, let compact, let text, let paper):
      try container.encode("Alert", forKey: .tag)
      fields = (noteId, author, compact, text, paper)
    case .liveActivity(let noteId, let author, let compact, let paper):
      try container.encode("LiveActivity", forKey: .tag)
      fields = (noteId, author, compact, nil, paper)
    case .reaction(let noteId, let by, let reaction):
      try container.encode("Reaction", forKey: .tag)
      try container.encode(noteId, forKey: .noteId)
      try container.encode(by, forKey: .by)
      try container.encode(reaction, forKey: .reaction)
      return
    }
    try container.encode(fields.0, forKey: .noteId)
    try container.encode(fields.1, forKey: .author)
    try container.encodeIfPresent(fields.2, forKey: .compact)
    try container.encodeIfPresent(fields.3, forKey: .text)
    try container.encodeIfPresent(fields.4, forKey: .paper)
  }
}
