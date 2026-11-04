/// Deletes the caller's account. A linked account sends the authorization code of a fresh Sign in
/// with Apple, so the server can revoke the app's Apple token.
public struct DeleteAccountRequest: Codable, Hashable, Sendable {
  public let appleAuthorizationCode: String?

  public init(appleAuthorizationCode: String? = nil) {
    self.appleAuthorizationCode = appleAuthorizationCode
  }
}
