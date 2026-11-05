public struct SessionResponse: Codable, Hashable, Sendable {
  public let sessionToken: SessionToken
  public let expiresAt: Int
  public let userId: UserId
  public let deviceId: DeviceId

  public init(sessionToken: SessionToken, expiresAt: Int, userId: UserId, deviceId: DeviceId) {
    self.sessionToken = sessionToken
    self.expiresAt = expiresAt
    self.userId = userId
    self.deviceId = deviceId
  }
}
