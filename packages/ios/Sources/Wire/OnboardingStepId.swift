/// Wire form of the contracts `OnboardingStepId`: a stable catalogue id. The server checks its
/// format; the client checks only that it is not empty.
public struct OnboardingStepId: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.rawValue = value
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard !value.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath, debugDescription: "OnboardingStepId must not be empty"))
    }
    rawValue = value
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
