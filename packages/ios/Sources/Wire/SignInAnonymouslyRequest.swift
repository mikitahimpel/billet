public struct SignInAnonymouslyRequest: Codable, Hashable, Sendable {
  public let accountKey: AccountKey

  public init(accountKey: AccountKey) {
    self.accountKey = accountKey
  }
}
