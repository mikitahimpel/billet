/// Wire form of the contracts `InviteCode`. The server checks its format; the client checks only
/// that it is not empty.
public struct InviteCode: Codable, Hashable, Sendable {
  public let rawValue: String

  /// The contract's `inviteCodeAlphabet` and `inviteCodeLength`; a test in contracts keeps them so.
  public static let alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
  public static let length = 10

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  /// What a person typed or pasted, without case, spaces or dashes.
  public static func normalized(_ typed: String) -> String {
    String(typed.uppercased().filter { !$0.isWhitespace && $0 != "-" })
  }

  /// Whether `normalized` uses only the alphabet's symbols, so far. A full code is also `length` long.
  public static func isPlausible(_ normalized: String) -> Bool {
    normalized.count <= length && normalized.allSatisfy { alphabet.contains($0) }
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard !value.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "InviteCode must not be empty"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
