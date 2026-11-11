import SwiftUI

/// A poster on a shelf that scrolls sideways: the art full bleed and square on top, the name on a
/// paper ribbon laid over the art's lower edge, and one status line under it. `emphasis` tints the
/// status when it asks something of the viewer ("Your turn"). The art is a `PosterScene`.
public struct PosterCard<Art: View>: View {
  let title: String
  let status: String
  let emphasis: Bool
  let action: () -> Void
  let art: Art
  @Environment(\.dynamicTypeSize) private var typeSize

  public init(
    _ title: String, status: String, emphasis: Bool = false, action: @escaping () -> Void,
    @ViewBuilder art: () -> Art
  ) {
    self.title = title
    self.status = status
    self.emphasis = emphasis
    self.action = action
    self.art = art()
  }

  public var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Color.clear
          // Wider at accessibility sizes, where posters stack full width and the words need the room.
          .aspectRatio(typeSize.isAccessibilitySize ? 3 / 2 : 1, contentMode: .fit)
          // Height from the width alone, so long words under it never squeeze the art narrower than the card.
          .fixedSize(horizontal: false, vertical: true)
          .overlay { art }
          .clipShape(
            UnevenRoundedRectangle(
              topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
          )
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Space.s) {
          ribbon
            .padding(.top, -PosterMetrics.ribbonOverlap)
          Text(status)
            .font(.ourioCallout.weight(emphasis ? .semibold : .medium))
            .foregroundStyle(emphasis ? Ink.accentText : Ink.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, CardMetrics.padding - Space.m)
        }
        .padding([.horizontal, .bottom], Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .cardSurface()
      .contentShape(.rect(cornerRadius: Radius.card))
    }
    .buttonStyle(PressScaleStyle())
    .accessibilityElement(children: .combine)
  }

  private var ribbon: some View {
    let paper = RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
    return Text(title)
      .font(.ourioHeadline)
      .foregroundStyle(Ink.heroInk)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Space.m)
      .padding(.vertical, Space.s)
      .background {
        paper.fill(Ink.paperEdge).offset(y: PosterMetrics.lip)
        paper.fill(Ink.paper)
      }
      .rotationEffect(.degrees(-2))
  }
}

enum PosterMetrics {
  /// How far the ribbon reaches up over the art.
  static let ribbonOverlap: CGFloat = Space.gutter
  static let lip: CGFloat = 3
}

/// A poster's art, composed from the app's own pictures: a warm wall with one pool of lamplight,
/// the cat, and one prop. Nothing in it moves.
public struct PosterScene: View {
  public enum Tone: Hashable, Sendable {
    case honey
    case rose
  }

  public enum Framing: Hashable, Sendable {
    /// Chest-up, the prop in front of her.
    case closeUp
    /// Whole, sitting on the floor beside the prop.
    case seated
  }

  public enum Prop {
    /// A paper card with one glyph on it.
    case note(symbol: String)
    /// A clay piece with its own soft shadow, as the shop's thumbnails are.
    case clay(Image)
  }

  let tone: Tone
  let framing: Framing
  let hero: Image?
  let prop: Prop?

  /// - Parameter hero: The seated cat, 3:4 on a clear ground.
  public init(tone: Tone, framing: Framing, hero: Image?, prop: Prop? = nil) {
    self.tone = tone
    self.framing = framing
    self.hero = hero
    self.prop = prop
  }

  public var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = proxy.size.height
      ZStack {
        Rectangle().fill(
          LinearGradient(
            stops: [
              .init(color: tone.wallTop, location: 0), .init(color: tone.wallMiddle, location: 0.6),
              .init(color: tone.wallBottom, location: 1),
            ], startPoint: .top, endPoint: .bottom))
        Rectangle().fill(
          EllipticalGradient(
            colors: [tone.light, tone.light.opacity(0)], center: tone.lightCentre,
            startRadiusFraction: 0, endRadiusFraction: 0.6))
        switch framing {
        case .closeUp: closeUp(width: width, height: height)
        case .seated: seated(width: width, height: height)
        }
      }
      .frame(width: width, height: height)
      .clipped()
    }
    .accessibilityHidden(true)
  }

  @ViewBuilder private func closeUp(width: CGFloat, height: CGFloat) -> some View {
    cat(height: height * 1.5)
      .position(x: width * 0.5 - height * 0.09, y: height * 0.66)
    let side = height * 0.34
    switch prop {
    case .note(let symbol):
      note(symbol, width: side)
        .rotationEffect(.degrees(8))
        .position(x: width * 0.91 - side / 2, y: height * 0.83 - side * 0.6)
    case .clay(let image):
      image.resizable().scaledToFit()
        .frame(width: side * 1.3, height: side * 1.3)
        .position(x: width * 0.94 - side * 0.65, y: height * 0.86 - side * 0.65)
    case nil:
      EmptyView()
    }
  }

  @ViewBuilder private func seated(width: CGFloat, height: CGFloat) -> some View {
    let floor = Ellipse()
    floor.fill(LinearGradient(colors: [tone.floorTop, tone.floorBottom], startPoint: .top, endPoint: .center))
      .overlay {
        floor.strokeBorder(
          LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center),
          lineWidth: 2)
      }
      .frame(width: width * 1.6, height: height * 0.62)
      .position(x: width / 2, y: height * 1.03)
    let catX = width * 0.5 + height * 0.126
    let side = height * 0.56
    switch prop {
    case .clay(let image):
      image.resizable().scaledToFit()
        .frame(width: side, height: side)
        .position(x: side * 0.47, y: height * 0.87 - side / 2)
    case .note(let symbol):
      note(symbol, width: height * 0.3)
        .rotationEffect(.degrees(-8))
        .position(x: width * 0.07 + height * 0.15, y: height * 0.3)
    case nil:
      EmptyView()
    }
    Ellipse()
      .fill(
        EllipticalGradient(
          colors: [tone.floorBottom.mix(with: Ink.heroInk, by: 0.6).opacity(0.5), .clear]))
      .frame(width: height * 0.46, height: height * 0.09)
      .position(x: catX, y: height * 0.8)
    cat(height: height * 0.84)
      .position(x: catX, y: height * 0.49)
  }

  @ViewBuilder private func cat(height: CGFloat) -> some View {
    if let hero {
      hero.resizable().scaledToFit().frame(height: height)
    }
  }

  private func note(_ symbol: String, width: CGFloat) -> some View {
    let paper = RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
    return Image(systemName: symbol)
      .font(.system(size: width * 0.5, weight: .heavy, design: .rounded))
      .foregroundStyle(Self.crayon)
      .frame(width: width, height: width * 1.2)
      .background {
        paper.fill(Ink.heroInk.opacity(0.14)).offset(y: width * 0.07)
        paper.fill(Ink.paperEdge).offset(y: width * 0.03)
        paper.fill(Ink.paper)
      }
  }

  private static let crayon = Color(hex: 0xE8704E)
}

extension PosterScene.Tone {
  var wallTop: Color {
    switch self {
    case .honey: Color(hex: 0xFFD596)
    case .rose: Color(hex: 0xEDC0AA)
    }
  }

  var wallMiddle: Color {
    switch self {
    case .honey: Color(hex: 0xF6AC64)
    case .rose: Color(hex: 0xDC9A86)
    }
  }

  var wallBottom: Color {
    switch self {
    case .honey: Color(hex: 0xEA8F52)
    case .rose: Color(hex: 0xC9786C)
    }
  }

  var light: Color {
    switch self {
    case .honey: Color(hex: 0xFFF3D6)
    case .rose: Color(hex: 0xFBE6D6)
    }
  }

  var lightCentre: UnitPoint {
    switch self {
    case .honey: UnitPoint(x: 0.22, y: 0.12)
    case .rose: UnitPoint(x: 0.78, y: 0.12)
    }
  }

  var floorTop: Color {
    switch self {
    case .honey: Color(hex: 0xD97F48)
    case .rose: Color(hex: 0x9C5450)
    }
  }

  var floorBottom: Color {
    switch self {
    case .honey: Color(hex: 0xC56A3A)
    case .rose: Color(hex: 0x8A4646)
    }
  }
}

#Preview("Poster card") {
  BothSchemes {
    HStack(alignment: .top, spacing: Space.m) {
      PosterCard("Who knows who", status: "Your turn, 3 left", emphasis: true, action: {}) {
        PosterScene(tone: .honey, framing: .closeUp, hero: nil, prop: .note(symbol: "questionmark"))
      }
      PosterCard("Draw & guess", status: "Alex is drawing", action: {}) {
        PosterScene(tone: .rose, framing: .seated, hero: nil, prop: .note(symbol: "scribble.variable"))
      }
    }
    .padding(Space.gutter)
  }
}
