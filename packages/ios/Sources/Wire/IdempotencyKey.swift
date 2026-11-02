import Foundation

/// Wire form of the contracts `IdempotencyKey`: a UUID the client makes once per note and repeats
/// on every retry of the same send.
public struct IdempotencyKey: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  /// A fresh key. Keep it with the unsent note and reuse it on each retry.
  public static func make() -> IdempotencyKey {
    IdempotencyKey(UUID().uuidString)
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard UUID(uuidString: value) != nil, value.count == 36 else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "IdempotencyKey must be a UUID"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
