/// The caller's account. `linked` is true once it can be recovered with Sign in with Apple.
/// `partnerLeft` is there while the caller is unpaired because their partner left; only
/// `GET /v1/account` fills it.
public struct AccountResponse: Codable, Hashable, Sendable {
  public let userId: UserId
  public let linked: Bool
  public let partnerLeft: PartnerLeft?

  public init(userId: UserId, linked: Bool, partnerLeft: PartnerLeft? = nil) {
    self.userId = userId
    self.linked = linked
    self.partnerLeft = partnerLeft
  }
}

/// The caller's last pair ended because the partner left, at `at` (epoch milliseconds).
public struct PartnerLeft: Codable, Hashable, Sendable {
  public enum Reason: String, Codable, Hashable, Sendable {
    case accountDeleted = "account-deleted"
  }

  public let reason: Reason
  public let at: Int

  public init(reason: Reason, at: Int) {
    self.reason = reason
    self.at = at
  }
}
