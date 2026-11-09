/// Wire form of the contracts `NoteStamp`: the postage stamp in a note's corner. The app owns the
/// art; the wire carries only the id.
public enum NoteStamp: String, Codable, Hashable, Sendable, CaseIterable {
  case heart
  case moon
  case bloom
  case paw
  case sun
}

/// Wire form of the contracts `NoteSeal`: the wax seal that closes a note.
public enum NoteSeal: String, Codable, Hashable, Sendable, CaseIterable {
  case rose
  case night
  case meadow
  case honey
  case plum
}
