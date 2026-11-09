/// 1 to 120 grapheme clusters (`String.count`, as the server counts), not only whitespace, and at
/// most 2048 UTF-16 units.
public struct NoteText: Codable, Hashable, Sendable {
  public static let maxCharacters = 120
  public static let maxUnits = 2048

  public let rawValue: String

  /// What JavaScript's `trim()` strips, the server's test for blank text. Swift's `isWhitespace`
  /// differs: it counts U+0085 and not U+FEFF.
  private static let blank = Set<Unicode.Scalar>(
    ([0x9, 0xA, 0xB, 0xC, 0xD, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
      + Array(0x2000...0x200A)).compactMap { Unicode.Scalar(UInt32($0)) })

  public static func accepts(_ text: String) -> Bool {
    !text.unicodeScalars.allSatisfy(blank.contains) && text.utf16.count <= maxUnits
      && text.count <= maxCharacters
  }

  /// `nil` for text the server would refuse.
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
