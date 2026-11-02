/// A stored note with its place in the couple's history, the same `seq` `NoteReceived` carries.
public struct NoteEntry: Codable, Hashable, Sendable {
  public let seq: Int
  public let note: Note

  public init(seq: Int, note: Note) {
    self.seq = seq
    self.note = note
  }
}

/// Oldest first. The next page starts after the last entry's `seq`.
public struct ListNotesResponse: Codable, Hashable, Sendable {
  public let notes: [NoteEntry]

  public init(notes: [NoteEntry]) {
    self.notes = notes
  }
}
