public struct SignInWithAppleRequest: Codable, Hashable, Sendable {
  public let identityToken: String

  public init(identityToken: String) {
    self.identityToken = identityToken
  }
}
