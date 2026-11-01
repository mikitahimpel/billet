public struct ListNotesResponse: Codable, Hashable, Sendable {
  public let notes: [Note]

  public init(notes: [Note]) {
    self.notes = notes
  }
}
