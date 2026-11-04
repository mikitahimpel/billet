/// The body of the 503 every write and the realtime socket get during maintenance. It is not an
/// ``ApiError``: `error` is always `maintenance`, and `status` is the service's whole status.
public struct MaintenanceResponse: Codable, Hashable, Sendable {
  public static let errorTag = "maintenance"

  public let error: String
  public let status: AppStatus

  public init(status: AppStatus) {
    self.error = Self.errorTag
    self.status = status
  }

  private enum CodingKeys: String, CodingKey {
    case error
    case status
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let error = try container.decode(String.self, forKey: .error)
    guard error == Self.errorTag else {
      throw DecodingError.dataCorruptedError(
        forKey: .error, in: container, debugDescription: "error must be \(Self.errorTag)")
    }
    self.error = error
    status = try container.decode(AppStatus.self, forKey: .status)
  }
}
