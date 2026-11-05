/// Wire form of the contracts `PaperColor`: the paper a note is written or drawn on. The app owns
/// the palette; the wire carries only the id.
public enum PaperColor: String, Codable, Hashable, Sendable, CaseIterable {
  case butter
  case blush
  case sage
  case sky
  case cream
}
