/// A note has two renditions: compact strokes for pushes, and a full PNG in R2.
public enum Note: Codable, Hashable, Sendable {
  case drawing(
    id: NoteId, author: UserId, sentAt: Int, compact: CompactStrokes, image: MediaKey)
  case photo(id: NoteId, author: UserId, sentAt: Int, image: MediaKey)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case id
    case author
    case sentAt
    case compact
    case image
  }

  /// `sentAt` is epoch milliseconds, which the contract requires to be zero or more.
  private static func sentAt(
    _ container: KeyedDecodingContainer<CodingKeys>
  ) throws -> Int {
    let value = try container.decode(Int.self, forKey: .sentAt)
    guard value >= 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .sentAt, in: container, debugDescription: "sentAt must not be negative")
    }
    return value
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Drawing":
      self = .drawing(
        id: try container.decode(NoteId.self, forKey: .id),
        author: try container.decode(UserId.self, forKey: .author),
        sentAt: try Self.sentAt(container),
        compact: try container.decode(CompactStrokes.self, forKey: .compact),
        image: try container.decode(MediaKey.self, forKey: .image))
    case "Photo":
      self = .photo(
        id: try container.decode(NoteId.self, forKey: .id),
        author: try container.decode(UserId.self, forKey: .author),
        sentAt: try Self.sentAt(container),
        image: try container.decode(MediaKey.self, forKey: .image))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .drawing(let id, let author, let sentAt, let compact, let image):
      try container.encode("Drawing", forKey: .tag)
      try container.encode(id, forKey: .id)
      try container.encode(author, forKey: .author)
      try container.encode(sentAt, forKey: .sentAt)
      try container.encode(compact, forKey: .compact)
      try container.encode(image, forKey: .image)
    case .photo(let id, let author, let sentAt, let image):
      try container.encode("Photo", forKey: .tag)
      try container.encode(id, forKey: .id)
      try container.encode(author, forKey: .author)
      try container.encode(sentAt, forKey: .sentAt)
      try container.encode(image, forKey: .image)
    }
  }
}
