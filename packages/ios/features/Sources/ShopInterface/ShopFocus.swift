/// Where the Shop opens when something elsewhere points at it, e.g. a locked ink in the drawing palette.
public enum ShopFocus: Hashable, Sendable {
  /// The Inks block in Today, at that ink.
  case ink(String)
  case item(String)
}
