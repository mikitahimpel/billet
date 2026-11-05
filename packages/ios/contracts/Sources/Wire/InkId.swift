/// Wire form of the contracts `InkId`: one ink colour, `ink-` and a kebab-case word.
public struct InkId: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  /// The ink every pair owns, and the one a text note without an ink is written in.
  public static let free = InkId("ink-graphite")

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard value.hasPrefix("ink-"), value.count > 4, value.count <= 40 else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "not an ink id: \(value)"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
