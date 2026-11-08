/// Why the caller reports their partner. A closed list: the server counts them.
public enum ReportReason: String, Codable, Hashable, Sendable, CaseIterable {
  case harassment
  case inappropriate
  case unsafe
  case spam
  case other
}

/// `POST /v1/pair/report`: reports the caller's partner to the team. The pair stays as it is.
/// `details` is never empty and at most 500 characters.
public struct ReportPartnerRequest: Codable, Hashable, Sendable {
  public let reason: ReportReason
  public let details: String?

  public init(reason: ReportReason, details: String? = nil) {
    self.reason = reason
    self.details = details
  }
}
