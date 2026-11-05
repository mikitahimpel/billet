/// Wire form of the contracts `SessionToken`: an opaque credential.
public struct SessionToken: Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Keeps the credential out of logs and string interpolation.
  public var description: String { "<redacted>" }

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard !value.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "SessionToken must not be empty"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
