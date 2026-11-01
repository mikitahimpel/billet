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

/// The shared ground of every screen: evening sky falling to green-black, with the lamp's light
/// resting near the top and a few sparkles.
public struct EveningBackground: View {
  private static let sparkles: [(x: Double, y: Double, size: CGFloat, opacity: Double)] = [
    (0.12, 0.07, 10, 0.7), (0.86, 0.11, 13, 0.85), (0.72, 0.04, 7, 0.45), (0.93, 0.34, 8, 0.4),
    (0.06, 0.29, 7, 0.4), (0.2, 0.52, 6, 0.25), (0.82, 0.62, 7, 0.25),
  ]

  public init() {}

  public var body: some View {
    GeometryReader { geometry in
      ZStack {
        LinearGradient(
          stops: [
            .init(color: Palette.sky.color, location: 0),
            .init(color: Palette.page.color, location: 0.5),
            .init(color: Palette.pageDeep.color, location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
        RadialGradient(
          colors: [Palette.light.color.opacity(0.14), .clear],
          center: UnitPoint(x: 0.5, y: 0.12),
          startRadius: 0,
          endRadius: max(geometry.size.width, 1) * 0.85
        )
        ForEach(Self.sparkles.indices, id: \.self) { index in
          let sparkle = Self.sparkles[index]
          Sparkle()
            .fill(Palette.gold.color.opacity(sparkle.opacity))
            .frame(width: sparkle.size, height: sparkle.size)
            .position(
              x: geometry.size.width * sparkle.x, y: geometry.size.height * sparkle.y)
        }
      }
    }
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

extension View {
  /// Stands this content on a lamp-lit panel: warm ground lifting towards the top corner, a lit
  /// hairline, and a soft shadow on the page.
  public func litPanel(cornerRadius: CGFloat = Radius.panel) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

  /// The screen title, in the one place and voice every tab uses.
  public func screenTitle() -> some View {
    billetType(.title)
      .foregroundStyle(Palette.paper.color)
      .accessibilityAddTraits(.isHeader)
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
        context.fill(Path(roundedRect: peg, cornerRadius: 2), with: .color(Palette.woodLit.color))
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

/// A question asked in the room's own light instead of a system sheet.
public struct EveningDialog<Actions: View>: View {
  private let title: String
  private let message: String
  private let actions: Actions

  public init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
    self.title = title
    self.message = message
    self.actions = actions()
  }

  public var body: some View {
    ZStack {
      Palette.pageDeep.color.opacity(0.7).ignoresSafeArea()
      ScrollView {
        VStack(spacing: Spacing.medium) {
          Text(title)
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
            .accessibilityAddTraits(.isHeader)
          Text(message)
            .billetType(.body)
            .foregroundStyle(Palette.paperTurned.color)
          actions
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.large)
        .litPanel()
        .padding(Spacing.large)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in length }
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .accessibilityAddTraits(.isModal)
  }
}

/// One tab of ``EveningTabBar``.
public struct EveningTab<ID: Hashable>: Identifiable {
  public let id: ID
  public let title: String
  public let systemImage: String

  public init(id: ID, title: String, systemImage: String) {
    self.id = id
    self.title = title
    self.systemImage = systemImage
  }
}

/// The tab bar: a low lit shelf with labels. The chosen tab catches the light.
public struct EveningTabBar<ID: Hashable>: View {
  private let tabs: [EveningTab<ID>]
  @Binding private var selection: ID

  public init(tabs: [EveningTab<ID>], selection: Binding<ID>) {
    self.tabs = tabs
    _selection = selection
  }

  public var body: some View {
    HStack(spacing: Spacing.hair) {
      ForEach(tabs) { tab in
        item(tab)
      }
    }
    .padding(Spacing.hair)
    .litPanel(cornerRadius: Radius.control + Spacing.hair)
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.hair)
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
  }

  private func item(_ tab: EveningTab<ID>) -> some View {
    let selected = tab.id == selection
    return Button {
      withAnimation(Motion.gentle) { selection = tab.id }
    } label: {
      VStack(spacing: 2) {
        Image(systemName: tab.systemImage)
          .font(.system(size: 18, weight: .medium))
          .frame(height: 22)
          .accessibilityHidden(true)
        Text(tab.title)
          .billetType(.caption)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .foregroundStyle((selected ? Palette.ink : Palette.muted).color)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background {
        if selected {
          RoundedRectangle(cornerRadius: Radius.control)
            .fill(Palette.gold.color)
            .lampGlow()
        }
      }
      .contentShape(.rect(cornerRadius: Radius.control))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
