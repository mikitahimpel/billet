/// Wire form of the contracts `AccountKey`: the secret that is the anonymous account.
/// 32 random bytes, base64url without padding. It lives in the iCloud Keychain and is never logged.
public struct AccountKey: Codable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  /// Keeps the secret out of logs and string interpolation.
  public var description: String { "<redacted>" }

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard !value.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "AccountKey must not be empty"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
