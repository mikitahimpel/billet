public struct CreateInviteResponse: Codable, Hashable, Sendable {
  public let code: InviteCode
  /// Epoch milliseconds when the server stops accepting `code`, zero or more.
  public let expiresAt: Int

  private enum CodingKeys: String, CodingKey {
    case code
    case expiresAt
  }

  public init(code: InviteCode, expiresAt: Int) {
    self.code = code
    self.expiresAt = expiresAt
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    code = try container.decode(InviteCode.self, forKey: .code)
    let value = try container.decode(Int.self, forKey: .expiresAt)
    guard value >= 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresAt, in: container, debugDescription: "expiresAt must not be negative")
    }
    expiresAt = value
  }
}
