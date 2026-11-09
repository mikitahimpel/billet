/// A closed list: the server counts them.
public enum ReportReason: String, Codable, Hashable, Sendable, CaseIterable {
  case harassment
  case inappropriate
  case unsafe
  case spam
  case other
}

/// The pair stays as it is. `details` is 1 to 500 characters. `noteId` names the note or photo,
/// when there is one.
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
