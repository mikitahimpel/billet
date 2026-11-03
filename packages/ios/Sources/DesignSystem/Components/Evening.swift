import SwiftUI

/// A four-point sparkle, the world's only ornament.
public struct Sparkle: Shape {
  public init() {}

  public func path(in rect: CGRect) -> Path {
    let (x, y) = (rect.midX, rect.midY)
    let (w, h) = (rect.width / 2, rect.height / 2)
    let pinch = 0.12
    var path = Path()
    path.move(to: CGPoint(x: x, y: y - h))
    path.addQuadCurve(
      to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w * pinch, y: y - h * pinch))
    path.addQuadCurve(
      to: CGPoint(x: x, y: y + h), control: CGPoint(x: x + w * pinch, y: y + h * pinch))
    path.addQuadCurve(
      to: CGPoint(x: x - w, y: y), control: CGPoint(x: x - w * pinch, y: y + h * pinch))
    path.addQuadCurve(
      to: CGPoint(x: x, y: y - h), control: CGPoint(x: x - w * pinch, y: y - h * pinch))
    path.closeSubpath()
    return path
  }
}

/// The shared ground of every screen, in the ground chosen in Labs (``EveningGround``): a sky
/// falling to the page's foot, the warm light it is lit by, and a little life of its own that
/// holds still when Reduce Motion is on.
public struct EveningBackground: View {
  @Environment(\.eveningGround) private var ground
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init() {}

  public var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack {
        LinearGradient(
          stops: [
            .init(color: ground.top.color, location: 0),
            .init(color: ground.middle.color, location: 0.5),
            .init(color: ground.foot.color, location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        light(size)
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { timeline in
          let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
          EveningLife(ground: ground, size: size, time: time)
        }
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }

  /// Where each ground's light rests.
  @ViewBuilder private func light(_ size: CGSize) -> some View {
    let width = max(size.width, 1)
    switch ground {
    case .ember:
      glow(ground.glow, 0.26, UnitPoint(x: 0.5, y: 1.05), width * 1.1)
      glow(Palette.light, 0.08, UnitPoint(x: 0.5, y: 0.08), width * 0.8)
    case .rose:
      glow(ground.glow, 0.2, UnitPoint(x: 0.22, y: 0.1), width * 0.9)
      glow(Swatch(0xE86A8A), 0.12, UnitPoint(x: 0.85, y: 0.55), width * 0.8)
    case .cocoa:
      glow(ground.glow, 0.14, UnitPoint(x: 0.5, y: 0.12), width * 0.9)
      glow(Swatch(0xD8705A), 0.08, UnitPoint(x: 0.5, y: 0.95), width)
    case .meadow:
      glow(Palette.light, 0.14, UnitPoint(x: 0.5, y: 0.12), width * 0.85)
    }
  }

  private func glow(_ colour: Swatch, _ opacity: Double, _ centre: UnitPoint, _ radius: CGFloat)
    -> some View
  {
    RadialGradient(
      colors: [colour.color.opacity(opacity), colour.color.opacity(0)], center: centre,
      startRadius: 0, endRadius: radius)
  }
}

/// The small moving things on a ground at `time`: sparks, sparkles or out-of-focus lights. Each
/// runs on its own clock, so the screen never shows the same picture twice.
struct EveningLife: View {
  let ground: EveningGround
  let size: CGSize
  let time: Double

  private static let sparkles: [(x: Double, y: Double, size: CGFloat, opacity: Double)] = [
    (0.12, 0.07, 10, 0.7), (0.86, 0.11, 13, 0.85), (0.72, 0.04, 7, 0.45), (0.93, 0.34, 8, 0.4),
    (0.06, 0.29, 7, 0.4), (0.2, 0.52, 6, 0.25), (0.82, 0.62, 7, 0.25),
  ]

  var body: some View {
    ZStack {
      switch ground {
      case .ember: sparks
      case .rose: sparkles(Swatch(0xF6C8A8), twinkle: true)
      case .cocoa: bokeh
      case .meadow: sparkles(Palette.gold, twinkle: false)
      }
    }
    .frame(width: size.width, height: size.height)
  }

  /// A number from 0 to 1 fixed for `index` and `salt`.
  static func hash(_ index: Int, _ salt: Double) -> Double {
    let value = sin(Double(index) * 12.9898 + salt * 78.233) * 43_758.5453
    return value - value.rounded(.down)
  }

  /// Sparks rising off the ember glow at the foot and fading as they climb.
  private var sparks: some View {
    ForEach(0..<22, id: \.self) { index in
      let a = Self.hash(index, 1)
      let b = Self.hash(index, 2)
      let c = Self.hash(index, 3)
      let period = 9 + 7 * b
      let rise = (time / period + c).truncatingRemainder(dividingBy: 1)
      let x = size.width * a + 14 * sin(time * (0.3 + 0.2 * b) + Double(index))
      let y = size.height * (1.02 - 0.55 * rise)
      let radius = 1.1 + 1.6 * c
      let colour = index % 3 == 0 ? Palette.light : EveningGround.ember.glow
      Circle()
        .fill(
          RadialGradient(
            colors: [colour.color, colour.color.opacity(0)], center: .center, startRadius: 0,
            endRadius: radius * 2.4)
        )
        .frame(width: radius * 4.8, height: radius * 4.8)
        .opacity(0.85 * sin(Double.pi * rise))
        .position(x: x, y: y)
    }
  }

  private func sparkles(_ colour: Swatch, twinkle: Bool) -> some View {
    ForEach(Self.sparkles.indices, id: \.self) { index in
      let sparkle = Self.sparkles[index]
      let shimmer =
        twinkle
        ? 0.65 + 0.35 * sin(time * (0.8 + 0.5 * Self.hash(index, 4)) + Double(index) * 2) : 1
      Sparkle()
        .fill(colour.color.opacity(sparkle.opacity * shimmer))
        .frame(width: sparkle.size, height: sparkle.size)
        .position(x: size.width * sparkle.x, y: size.height * sparkle.y)
    }
  }

  /// Soft round lights out of focus, drifting slowly.
  private var bokeh: some View {
    ForEach(0..<14, id: \.self) { index in
      let a = Self.hash(index, 5)
      let b = Self.hash(index, 6)
      let c = Self.hash(index, 7)
      let x = size.width * a + 22 * sin(time * 0.05 * (1 + b) + Double(index))
      let y = size.height * (0.05 + 0.85 * b) + 16 * cos(time * 0.04 * (1 + c) + Double(index) * 2)
      let radius = 18 + 46 * c
      let colour = index % 3 == 1 ? Swatch(0xE89A8A) : EveningGround.cocoa.glow
      Circle()
        .fill(
          RadialGradient(
            colors: [
              colour.color.opacity(0.9), colour.color.opacity(0.6), colour.color.opacity(0),
            ],
            center: .center, startRadius: 0, endRadius: radius)
        )
        .frame(width: radius * 2, height: radius * 2)
        .opacity(0.05 + 0.09 * a)
        .position(x: x, y: y)
    }
  }
}

extension View {
  /// The app's one card: a lamp-lit ground lifting towards the top corner, a lit hairline, and a
  /// soft shadow on the page.
  public func card() -> some View {
    let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    return
      self
      .background {
        shape
          .fill(
            LinearGradient(
              colors: [Palette.raisedTop.color, Palette.raised.color],
              startPoint: .topLeading,
              endPoint: UnitPoint(x: 0.6, y: 0.7)
            )
          )
          .shadow(
            color: Palette.pageDeep.color.opacity(Glow.panelShadowOpacity),
            radius: Glow.panelShadow,
            y: Spacing.small
          )
      }
      .overlay {
        shape.strokeBorder(Palette.lightWarm.color.opacity(Glow.edgeOpacity), lineWidth: 1)
      }
  }

  /// The soft halo around anything that gives light.
  public func lampGlow() -> some View {
    shadow(color: Palette.light.color.opacity(Glow.lampOpacity), radius: Glow.lamp)
  }
}

/// The frame of a tab: the evening behind, one title, and content that scrolls under the glass.
public struct ScreenScaffold<Content: View>: View {
  private let title: String
  private let content: Content

  public init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
          Text(title)
            .billetType(.title)
            .foregroundStyle(Palette.paper.color)
            .accessibilityAddTraits(.isHeader)
          content
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }
}

/// The app's one list row. `leading` and `trailing` hold whatever the row needs at its edges.
public struct ListRow<Leading: View, Trailing: View>: View {
  private let title: String
  private let subtitle: String?
  private let leading: Leading
  private let trailing: Trailing

  public init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.leading = leading()
    self.trailing = trailing()
  }

  @Environment(\.dynamicTypeSize) private var typeSize

  public var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        // At the largest text sizes a side-by-side row leaves the words a column a letter wide, so
        // the pieces stack and the words get the whole width.
        VStack(alignment: .leading, spacing: Spacing.small) {
          leading
          texts
          trailing
        }
      } else {
        HStack(spacing: Spacing.medium) {
          leading
          texts
            .frame(maxWidth: .infinity, alignment: .leading)
          trailing
        }
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small)
    .frame(maxWidth: .infinity, minHeight: Target.row, alignment: .leading)
    .contentShape(.rect)
  }

  private var texts: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
      if let subtitle {
        Text(subtitle)
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .contentTransition(.opacity)
      }
    }
  }
}

/// The hairline between rows in one card.
public struct ListDivider: View {
  public init() {}

  public var body: some View {
    Palette.paper.color.opacity(0.1)
      .frame(height: 1)
      .padding(.leading, Spacing.medium)
      .accessibilityHidden(true)
  }
}

/// A trailing symbol in a list row, in the app's one icon weight.
public struct RowIcon: View {
  private let systemImage: String
  private let color: Swatch

  public init(_ systemImage: String, color: Swatch = Palette.muted) {
    self.systemImage = systemImage
    self.color = color
  }

  public var body: some View {
    Image(systemName: systemImage)
      .font(IconStyle.font)
      .foregroundStyle(color.color)
      .accessibilityHidden(true)
  }
}

/// A spinner and what it is waiting for.
public struct LoadingLine: View {
  private let text: String

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    HStack(spacing: Spacing.small) {
      ProgressView().tint(Palette.gold.color)
      Text(text)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(minHeight: Target.minimum)
    .accessibilityElement(children: .combine)
  }
}

/// A title, a line of explanation and a little empty wire with its two pegs.
public struct EmptyWire: View {
  private let title: String
  private let message: String

  public init(title: String, message: String) {
    self.title = title
    self.message = message
  }

  public var body: some View {
    VStack(spacing: Spacing.medium) {
      wire
      VStack(spacing: Spacing.small) {
        Text(title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text(message)
          .billetType(.body)
          .foregroundStyle(Palette.muted.color)
      }
      .multilineTextAlignment(.center)
      .accessibilityElement(children: .combine)
    }
    .padding(Spacing.wide)
    .frame(maxWidth: .infinity)
  }

  private var wire: some View {
    Canvas { context, size in
      var line = Path()
      line.move(to: CGPoint(x: 0, y: 8))
      line.addQuadCurve(
        to: CGPoint(x: size.width, y: 8), control: CGPoint(x: size.width / 2, y: 26))
      context.stroke(
        line, with: .color(Palette.paperTurned.color),
        style: StrokeStyle(lineWidth: 2, lineCap: .round))
      for x in [size.width * 0.32, size.width * 0.68] {
        let peg = CGRect(x: x - 2.5, y: 8, width: 5, height: 18)
        context.fill(
          Path(roundedRect: peg, cornerRadius: Radius.peg), with: .color(Palette.woodLit.color))
      }
    }
    .frame(width: 180, height: 32)
    .overlay(alignment: .topTrailing) {
      Sparkle()
        .fill(Palette.gold.color)
        .frame(width: 12, height: 12)
        .offset(x: 14, y: -12)
    }
    .accessibilityHidden(true)
  }
}
