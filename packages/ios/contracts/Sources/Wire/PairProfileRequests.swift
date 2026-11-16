/// `PUT /v1/me`: nil forgets the caller's name. The server takes 1 to 40 trimmed characters
/// without control characters.
public struct SetDisplayNameRequest: Codable, Hashable, Sendable {
  public let displayName: String?

  public init(displayName: String?) {
    self.displayName = displayName
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(displayName, forKey: .displayName)
  }

  private enum CodingKeys: String, CodingKey {
    case displayName
  }
}

/// `PUT /v1/pair/together-since`. `ifUnset`: only while no partner has set the pair's day.
public struct SetTogetherSinceRequest: Codable, Hashable, Sendable {
  /// YYYY-MM-DD.
  public let day: String
  public let ifUnset: Bool?

  public init(day: String, ifUnset: Bool? = nil) {
    self.day = day
    self.ifUnset = ifUnset
  }
}
