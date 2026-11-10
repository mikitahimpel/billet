import SwiftUI

/// A glyph on a solid tinted disc at the corner of an avatar or a glass control: what it wants or
/// holds, shown only while that matters. The ring is `Ink.glassFill`, as on `glassBadge`, so it
/// stays apart from the glass under it; the glyph is `Ink.heroInk`, which reads on honey and blush.
public struct SymbolBadge: View {
  static let size: CGFloat = 22

  let symbol: String
  let tint: Color

  public init(symbol: String, tint: Color = .honey) {
    self.symbol = symbol
    self.tint = tint
  }

  public var body: some View {
    Image(systemName: symbol)
      .font(.system(size: Self.size * 0.5, weight: .bold))
      .foregroundStyle(Ink.heroInk)
      .frame(width: Self.size, height: Self.size)
      .background(tint, in: .circle)
      .overlay(Circle().strokeBorder(Ink.glassFill, lineWidth: 1.5))
      .accessibilityHidden(true)
  }
}

#Preview("Symbol badge") {
  BothSchemes {
    HStack(spacing: Space.xl) {
      Circle().fill(Ink.surfaceRaised)
        .frame(width: Size.control, height: Size.control)
        .overlay(alignment: .topTrailing) { SymbolBadge(symbol: "fork.knife") }
      Circle().fill(Ink.surfaceRaised)
        .frame(width: Size.control, height: Size.control)
        .overlay(alignment: .topTrailing) {
          SymbolBadge(symbol: "heart.fill", tint: .blushPink)
        }
    }
    .padding(Space.gutter)
    .background(RoomBackdrop())
  }
}
