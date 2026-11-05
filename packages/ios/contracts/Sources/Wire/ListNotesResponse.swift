/// A stored note with its place in the couple's history, the same `seq` `NoteReceived` carries.
public struct NoteEntry: Codable, Hashable, Sendable {
  public let seq: Int
  public let note: Note

  public init(seq: Int, note: Note) {
    self.seq = seq
    self.note = note
  }
}

/// Oldest first. The next page starts after `lastSeq`.
public struct ListNotesResponse: Codable, Hashable, Sendable {
  /// The entries this build can read.
  public let notes: [NoteEntry]
  /// The last entry's `seq`, counting one this build can't read, so a cursor moves past it; `nil`
  /// for an empty page.
  public let lastSeq: Int?

  public init(notes: [NoteEntry], lastSeq: Int? = nil) {
    self.notes = notes
    self.lastSeq = lastSeq ?? notes.last?.seq
  }

  private enum CodingKeys: String, CodingKey {
    case notes
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let entries = try container.decode([LossyEntry].self, forKey: .notes)
    notes = entries.compactMap { entry in entry.note.map { NoteEntry(seq: entry.seq, note: $0) } }
    lastSeq = entries.last?.seq
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(notes, forKey: .notes)
  }

  /// An entry's `seq` always, its note only when this build knows its kind.
  private struct LossyEntry: Decodable {
    let seq: Int
    let note: Note?

    private enum CodingKeys: String, CodingKey {
      case seq
      case note
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      seq = try container.decode(Int.self, forKey: .seq)
      note = try? container.decode(Note.self, forKey: .note)
    }
  }
}
