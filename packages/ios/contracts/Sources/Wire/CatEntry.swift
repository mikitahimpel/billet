/// `at` is the server's clock in epoch milliseconds. `id` is the phone's UUID and also the
/// `LifeEvent` id; `seq` orders the journal and is what a reconnect resumes from.
public struct CatEntry: Codable, Hashable, Sendable {
  public let seq: Int
  public let id: IdempotencyKey
  public let by: UserId
  public let at: Int
  public let event: CatEvent

  public init(seq: Int, id: IdempotencyKey, by: UserId, at: Int, event: CatEvent) {
    self.seq = seq
    self.id = id
    self.by = by
    self.at = at
    self.event = event
  }
}

/// Oldest first. The next page starts after the last entry's `seq`.
public struct CatJournalResponse: Codable, Hashable, Sendable {
  public let entries: [CatEntry]

  public init(entries: [CatEntry]) {
    self.entries = entries
  }
}
