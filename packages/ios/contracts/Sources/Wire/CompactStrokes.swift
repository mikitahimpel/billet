/// Compact vector rendition that travels inside a push.
public struct CompactStrokes: Codable, Hashable, Sendable {
  public let strokes: [CompactStroke]

  public init(strokes: [CompactStroke]) {
    self.strokes = strokes
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case strokes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .version, in: container, debugDescription: "unsupported version \(version)")
    }
    strokes = try container.decode([CompactStroke].self, forKey: .strokes)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(strokes, forKey: .strokes)
  }
}
