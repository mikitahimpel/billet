public struct ClaimInviteResponse: Codable, Hashable, Sendable {
  public let pairId: PairId

  public init(pairId: PairId) {
    self.pairId = pairId
  }
}
