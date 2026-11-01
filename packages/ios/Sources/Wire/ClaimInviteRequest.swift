public struct ClaimInviteRequest: Codable, Hashable, Sendable {
  public let code: InviteCode

  public init(code: InviteCode) {
    self.code = code
  }
}
