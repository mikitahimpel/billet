/// Wire form of the contracts `NoteText`: what a text note says. 1 to 120 characters as a person
/// counts them (Swift's `String.count`, the same grapheme clusters the server counts), not only
/// whitespace, and at most 2048 UTF-16 units.
public struct NoteText: Codable, Hashable, Sendable {
  public static let maxCharacters = 120
  public static let maxUnits = 2048

  public let rawValue: String

  /// Whether the server would take `text` as a text note.
  public static func accepts(_ text: String) -> Bool {
    !text.allSatisfy(\.isWhitespace) && text.utf16.count <= maxUnits
      && text.count <= maxCharacters
  }

  /// `nil` for text the server would refuse, so a composer can't send one.
  public init?(validating text: String) {
    guard Self.accepts(text) else { return nil }
    rawValue = text
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard Self.accepts(value) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "NoteText must be 1 to \(Self.maxCharacters) characters"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
