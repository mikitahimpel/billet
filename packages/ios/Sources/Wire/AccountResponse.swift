/// The caller's account. `linked` is true once it can be recovered with Sign in with Apple.
public struct AccountResponse: Codable, Hashable, Sendable {
  public let userId: UserId
  public let linked: Bool

  public init(userId: UserId, linked: Bool) {
    self.userId = userId
    self.linked = linked
  }
}
