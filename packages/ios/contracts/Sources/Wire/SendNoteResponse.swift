public struct SendNoteResponse: Codable, Hashable, Sendable {
  public let note: Note

  public init(note: Note) {
    self.note = note
  }
}
