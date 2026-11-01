public struct AuthChallengeResponse: Codable, Hashable, Sendable {
  public let nonce: AuthNonce
  public let expiresAt: Int

  public init(nonce: AuthNonce, expiresAt: Int) {
    self.nonce = nonce
    self.expiresAt = expiresAt
  }
}
