/// The app owns the art; the wire carries only the id.
public enum NoteStamp: String, Codable, Hashable, Sendable, CaseIterable {
  case heart
  case moon
  case bloom
  case paw
  case sun
}

public enum NoteSeal: String, Codable, Hashable, Sendable, CaseIterable {
  case rose
  case night
  case meadow
  case honey
  case plum
}
