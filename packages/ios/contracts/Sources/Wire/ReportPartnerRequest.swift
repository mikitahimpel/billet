/// Why the caller reports their partner. A closed list: the server counts them.
public enum ReportReason: String, Codable, Hashable, Sendable, CaseIterable {
  case harassment
  case inappropriate
  case unsafe
  case spam
  case other
}

/// `POST /v1/pair/report`: reports the caller's partner to the team. The pair stays as it is.
/// `details` is never empty and at most 500 characters. `noteId` names the one note or photo the
/// report is about, when there is one.
public struct ReportPartnerRequest: Codable, Hashable, Sendable {
  public let reason: ReportReason
  public let noteId: NoteId?
  public let details: String?

  public init(reason: ReportReason, noteId: NoteId? = nil, details: String? = nil) {
    self.reason = reason
    self.noteId = noteId
    self.details = details
  }
}
