public struct RegisterPushTokenRequest: Codable, Hashable, Sendable {
  public let kind: PushTokenKind
  public let environment: ApnsEnvironment
  public let token: PushToken

  public init(kind: PushTokenKind, environment: ApnsEnvironment, token: PushToken) {
    self.kind = kind
    self.environment = environment
    self.token = token
  }
}
