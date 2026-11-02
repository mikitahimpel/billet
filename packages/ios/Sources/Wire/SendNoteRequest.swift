/// The server assigns id, author and time. Sending the same `key` again returns the first note
/// instead of storing another.
public enum SendNoteRequest: Codable, Hashable, Sendable {
  case drawing(key: IdempotencyKey, compact: CompactStrokes, image: MediaKey)
  case photo(key: IdempotencyKey, image: MediaKey)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case key
    case compact
    case image
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Drawing":
      self = .drawing(
        key: try container.decode(IdempotencyKey.self, forKey: .key),
        compact: try container.decode(CompactStrokes.self, forKey: .compact),
        image: try container.decode(MediaKey.self, forKey: .image))
    case "Photo":
      self = .photo(
        key: try container.decode(IdempotencyKey.self, forKey: .key),
        image: try container.decode(MediaKey.self, forKey: .image))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .drawing(let key, let compact, let image):
      try container.encode("Drawing", forKey: .tag)
      try container.encode(key, forKey: .key)
      try container.encode(compact, forKey: .compact)
      try container.encode(image, forKey: .image)
    case .photo(let key, let image):
      try container.encode("Photo", forKey: .tag)
      try container.encode(key, forKey: .key)
      try container.encode(image, forKey: .image)
    }
  }
}
