import Foundation

/// Made once per send and repeated on every retry of it.
public struct IdempotencyKey: Codable, Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

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
