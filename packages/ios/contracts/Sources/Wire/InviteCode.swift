/// The server checks its format; the client checks only that it is not empty.
public struct InviteCode: Codable, Hashable, Sendable {
  public let rawValue: String

  /// The contract's `inviteCodeAlphabet` and `inviteCodeLength`; a test in contracts keeps them so.
  public static let alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
  public static let length = 10
  /// The contract's `reviewCodeLength`: the App Review pair's code, typed in the same field.
  public static let reviewLength = 26

  /// Claimed on its own route.
  public var isReview: Bool { rawValue.count == Self.reviewLength }

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  /// Drops case, spaces and dashes.
  public static func normalized(_ typed: String) -> String {
    String(typed.uppercased().filter { !$0.isWhitespace && $0 != "-" })
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
