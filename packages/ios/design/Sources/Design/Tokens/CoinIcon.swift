import SwiftUI

/// The dark ring keeps it apart from honey buttons and from any dark surface.
/// With `relativeTo`, it grows and shrinks with Dynamic Type as that text style does, so it keeps
/// its size beside the digits it counts; without, it is art at a fixed size.
public struct CoinIcon: View {
  let base: CGFloat
  let scales: Bool
  @ScaledMetric private var scaled: CGFloat

  public init(size: CGFloat = 16, relativeTo style: Font.TextStyle? = nil) {
    base = size
    scales = style != nil
    _scaled = ScaledMetric(wrappedValue: size, relativeTo: style ?? .body)
  }

  private var size: CGFloat { scales ? scaled : base }

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
