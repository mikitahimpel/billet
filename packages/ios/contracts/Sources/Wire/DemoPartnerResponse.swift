/// Dev server only: whether the caller is paired with their bot partner.
public struct DemoPartnerResponse: Codable, Hashable, Sendable {
  public let paired: Bool

  public init(paired: Bool) {
    self.paired = paired
  }
}
