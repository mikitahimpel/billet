/// The server assigns id, author and time. The same `key` again returns the first note.
public enum SendNoteRequest: Codable, Hashable, Sendable {
  case drawing(
    key: IdempotencyKey, compact: CompactStrokes, image: MediaKey, paper: PaperColor? = nil,
    stamp: NoteStamp? = nil, seal: NoteSeal? = nil)
  /// Already uploaded to `POST /v1/media`; 1 to 8192 pixels a side.
  case photo(
    key: IdempotencyKey, image: MediaKey, width: Int, height: Int, preview: String,
    caption: NoteText? = nil)
  /// `ink` must be one the pair owns, or the server answers `ApiError.inkNotOwned`.
  case text(
    key: IdempotencyKey, text: NoteText, paper: PaperColor? = nil, stamp: NoteStamp? = nil,
    seal: NoteSeal? = nil, ink: InkId = .free)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case key
    case compact
    case image
    case text
    case paper
    case stamp
    case seal
    case width
    case height
    case preview
    case caption
    case ink
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Drawing":
      self = .drawing(
        key: try container.decode(IdempotencyKey.self, forKey: .key),
        compact: try container.decode(CompactStrokes.self, forKey: .compact),
        image: try container.decode(MediaKey.self, forKey: .image),
        paper: try container.decodeOptionalKey(PaperColor.self, forKey: .paper),
        stamp: try container.decodeOptionalKey(NoteStamp.self, forKey: .stamp),
        seal: try container.decodeOptionalKey(NoteSeal.self, forKey: .seal))
    case "Photo":
      self = .photo(
        key: try container.decode(IdempotencyKey.self, forKey: .key),
        image: try container.decode(MediaKey.self, forKey: .image),
        width: try container.decode(Int.self, forKey: .width),
        height: try container.decode(Int.self, forKey: .height),
        preview: try container.decode(String.self, forKey: .preview),
        caption: try container.decodeOptionalKey(NoteText.self, forKey: .caption))
    case "Text":
      self = .text(
        key: try container.decode(IdempotencyKey.self, forKey: .key),
        text: try container.decode(NoteText.self, forKey: .text),
        paper: try container.decodeOptionalKey(PaperColor.self, forKey: .paper),
        stamp: try container.decodeOptionalKey(NoteStamp.self, forKey: .stamp),
        seal: try container.decodeOptionalKey(NoteSeal.self, forKey: .seal),
        ink: try container.decodeOptionalKey(InkId.self, forKey: .ink) ?? .free)
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .drawing(let key, let compact, let image, let paper, let stamp, let seal):
      try container.encode("Drawing", forKey: .tag)
      try container.encode(key, forKey: .key)
      try container.encode(compact, forKey: .compact)
      try container.encode(image, forKey: .image)
      try container.encodeIfPresent(paper, forKey: .paper)
      try container.encodeIfPresent(stamp, forKey: .stamp)
      try container.encodeIfPresent(seal, forKey: .seal)
    case .photo(let key, let image, let width, let height, let preview, let caption):
      try container.encode("Photo", forKey: .tag)
      try container.encode(key, forKey: .key)
      try container.encode(image, forKey: .image)
      try container.encode(width, forKey: .width)
      try container.encode(height, forKey: .height)
      try container.encode(preview, forKey: .preview)
      try container.encodeIfPresent(caption, forKey: .caption)
    case .text(let key, let text, let paper, let stamp, let seal, let ink):
      try container.encode("Text", forKey: .tag)
      try container.encode(key, forKey: .key)
      try container.encode(text, forKey: .text)
      try container.encodeIfPresent(paper, forKey: .paper)
      try container.encodeIfPresent(stamp, forKey: .stamp)
      try container.encodeIfPresent(seal, forKey: .seal)
      try container.encode(ink, forKey: .ink)
    }
  }
}
