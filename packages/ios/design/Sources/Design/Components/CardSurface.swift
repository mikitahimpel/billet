import SwiftUI

public enum CardState: Hashable, Sendable {
  case rest
  /// A honey ring in place of the highlight edge.
  case selected
  /// Flat: no light, no edge, no shadow. Its labels take `Ink.disabledText`.
  case disabled
}

extension View {
  /// The card: an opaque fill lit from above, a hairline of light on its upper edge and a soft shadow
  /// under it. `warm` is for a screen's one hero card. Also the container shape, so a
  /// `ConcentricRectangle` inside follows its corners.
  public func cardSurface(
    radius: CGFloat = Radius.card, warm: Bool = false, state: CardState = .rest
  ) -> some View {
    modifier(CardSurface(radius: radius, warm: warm, state: state))
  }

  /// The card's shadow alone, for a card that draws a fill of its own.
  public func cardShadow() -> some View {
    background { CardShadow() }
  }
}

private struct CardSurface: ViewModifier {
  let radius: CGFloat
  let warm: Bool
  let state: CardState

  private var shape: CardShape { CardShape(radius: radius) }

  func body(content: Content) -> some View {
    content
      .background { fill }
      .overlay { edge }
      .containerShape(shape)
  }

  @ViewBuilder private var fill: some View {
    switch state {
    case .disabled:
      shape.fill(Ink.disabledFill)
    case .rest, .selected:
      CardShadow()
      if warm {
        shape.fill(Ink.warmFill)
        shape.fill(
          EllipticalGradient(
            colors: [Ink.warmGlow, Ink.warmGlow.opacity(0)], center: UnitPoint(x: 0.85, y: 0),
            startRadiusFraction: 0, endRadiusFraction: 0.6))
      } else {
        shape.fill(Ink.cardFill)
      }
    }
  }

  @ViewBuilder private var edge: some View {
    switch state {
    case .rest:
      shape.strokeBorder(
        LinearGradient(
          stops: [
            .init(color: Ink.cardRimTop, location: 0),
            .init(color: Ink.cardRimBottom, location: 0.55),
          ],
          startPoint: .top, endPoint: .bottom),
        lineWidth: 1
      )
      .allowsHitTesting(false)
    case .selected:
      shape.strokeBorder(Color.honey, lineWidth: 2).allowsHitTesting(false)
    case .disabled:
      EmptyView()
    }
  }
}

/// The card's outline. A card not much taller than two of its corners would turn into a capsule, so
/// its corners tighten with its height and a one-row card stays a card.
struct CardShape: InsettableShape {
  var radius: CGFloat
  var inset: CGFloat = 0

  static let heightShare: CGFloat = 0.38

  func path(in rect: CGRect) -> Path {
    let fitted = min(radius, rect.height * Self.heightShare)
    return RoundedRectangle(cornerRadius: max(0, fitted - inset), style: .continuous)
      .path(in: rect.insetBy(dx: inset, dy: inset))
  }

  func inset(by amount: CGFloat) -> CardShape {
    CardShape(radius: radius, inset: inset + amount)
  }
}

/// The shadow under a card, stretched from one small picture drawn once for each appearance: a
/// scroll moves a texture and never runs a blur.
struct CardShadow: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    if let image = Self.image(colorScheme) {
      image
        .resizable(
          capInsets: EdgeInsets(
            top: Self.cap, leading: Self.cap, bottom: Self.cap, trailing: Self.cap),
          resizingMode: .stretch
        )
        .padding(-Self.outset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  /// How far the picture reaches past the card on every side.
  static let outset: CGFloat = 24
  /// The corner kept unstretched.
  static let cap: CGFloat = outset + Radius.card
  private static let scale: CGFloat = 3

  @MainActor private static var drawn: [ColorScheme: Image] = [:]

  @MainActor static func image(_ scheme: ColorScheme) -> Image? {
    if let image = drawn[scheme] { return image }
    let renderer = ImageRenderer(content: picture(scheme))
    renderer.scale = scale
    guard let rendered = renderer.cgImage else { return nil }
    let image = Image(decorative: rendered, scale: scale)
    drawn[scheme] = image
    return image
  }

  private static func picture(_ scheme: ColorScheme) -> some View {
    let side = 2 * (cap - outset) + 1
    let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    let color = Palette.cardShadow.value(scheme == .dark ? .dark : .light).color
    return ZStack {
      shape.fill(color).padding(.horizontal, 4).blur(radius: 9).offset(y: 6)
      shape.fill(color.opacity(0.5)).blur(radius: 1).offset(y: 1)
    }
    .frame(width: side, height: side)
    .padding(outset)
  }
}

#Preview("Card surface") {
  BothSchemes {
    VStack(spacing: Space.m) {
      Card(warm: true) { Text("Warm").font(.ourioHeadline).foregroundStyle(Ink.text) }
      Card { Text("Rest").font(.ourioHeadline).foregroundStyle(Ink.text) }
      Card(state: .selected) { Text("Selected").font(.ourioHeadline).foregroundStyle(Ink.text) }
      Card(state: .disabled) {
        Text("Disabled").font(.ourioHeadline).foregroundStyle(Ink.disabledText)
      }
    }
    .padding(Space.gutter)
  }
}
