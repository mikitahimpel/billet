public enum ApiError: Codable, Hashable, Sendable {
  case unauthorized
  case invalidRequest
  case unavailable
  case notFound
  case invalidInvite
  case alreadyPaired
  /// The Apple ID is already linked to another account.
  case appleIdInUse
  /// The server would not credit a purchase: its signature, bundle, environment or product.
  case invalidPurchase

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Unauthorized": self = .unauthorized
    case "InvalidRequest": self = .invalidRequest
    case "Unavailable": self = .unavailable
    case "NotFound": self = .notFound
    case "InvalidInvite": self = .invalidInvite
    case "AlreadyPaired": self = .alreadyPaired
    case "AppleIdInUse": self = .appleIdInUse
    case "InvalidPurchase": self = .invalidPurchase
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .unauthorized: try container.encode("Unauthorized", forKey: .tag)
    case .invalidRequest: try container.encode("InvalidRequest", forKey: .tag)
    case .unavailable: try container.encode("Unavailable", forKey: .tag)
    case .notFound: try container.encode("NotFound", forKey: .tag)
    case .invalidInvite: try container.encode("InvalidInvite", forKey: .tag)
    case .alreadyPaired: try container.encode("AlreadyPaired", forKey: .tag)
    case .appleIdInUse: try container.encode("AppleIdInUse", forKey: .tag)
    case .invalidPurchase: try container.encode("InvalidPurchase", forKey: .tag)
    }
  }
}
