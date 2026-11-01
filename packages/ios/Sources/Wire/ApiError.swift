public enum ApiError: Codable, Hashable, Sendable {
  case unauthorized
  case notFound
  case invalidInvite

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Unauthorized": self = .unauthorized
    case "NotFound": self = .notFound
    case "InvalidInvite": self = .invalidInvite
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .unauthorized: try container.encode("Unauthorized", forKey: .tag)
    case .notFound: try container.encode("NotFound", forKey: .tag)
    case .invalidInvite: try container.encode("InvalidInvite", forKey: .tag)
    }
  }
}
