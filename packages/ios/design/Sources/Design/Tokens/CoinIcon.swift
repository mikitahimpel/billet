import SwiftUI

/// The dark ring keeps it apart from honey buttons and from any dark surface.
public struct CoinIcon: View {
  var size: CGFloat

  public init(size: CGFloat = 16) { self.size = size }

  public var body: some View {
    ZStack {
      Circle().fill(Palette.coinFace.color)
      Image(systemName: "star.fill")
        .font(.system(size: size * 0.42, weight: .bold))
        .foregroundStyle(Ink.heroInk)
    }
    .frame(width: size, height: size)
    .overlay { Circle().strokeBorder(Palette.coinRing.color, lineWidth: max(1.25, size * 0.09)) }
    .accessibilityHidden(true)
  }
}

#Preview("Coin") {
  HStack(spacing: Space.l) {
    CoinIcon(size: 24)
    PriceButton(120) {}
    Text("Honey").padding(Space.m).background(Color.honey, in: .capsule)
  }
  .padding(Space.gutter)
  .background(Ink.screen)
}
