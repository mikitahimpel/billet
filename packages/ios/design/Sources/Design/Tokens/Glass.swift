import SwiftUI

/// Perf-run arms (`-perf.hud opaque|flat`): `opaque` adds a shadow, `flat` none; neither uses
/// a `GlassEffectContainer`.
public enum GlassRendering: Sendable {
  case liquid
  case opaque
  case flat
}

extension EnvironmentValues {
  @Entry public var glassRendering: GlassRendering = .liquid
}

/// Every floating surface picks a role; the role fixes the rest. With Reduce Transparency the
/// tint is drawn solid as `Ink.surface`.
public enum GlassRole: Sendable {
  case control
  /// Holds several controls that respond themselves, so the glass is not interactive.
  case bar
}

/// `blend` < `gap`, so neighbours morph when they appear but never merge at rest.
public enum GlassMetrics {
  public static let blend: CGFloat = Space.s
  public static let gap: CGFloat = Space.s + 2
  public static let rim: CGFloat = 1
  /// How far a badge reaches past its control's corner.
  public static let badgeOverhang: CGFloat = Space.xs
}

extension View {
  /// Apply after the content's other modifiers: it captures them.
  public func glass<S: InsettableShape>(_ shape: S, role: GlassRole) -> some View {
    modifier(RoleGlass(shape: shape, role: role))
  }

  /// For art inside content and full-screen canvases; chrome uses `glass(_:role:)`.
  public func glass<S: Shape>(
    _ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false
  ) -> some View {
    modifier(GlassModifier(shape: shape, tint: tint, clear: clear, interactive: interactive))
  }

  public func warmGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
    glass(shape, tint: Ink.glassTint, clear: true, interactive: interactive)
  }

  @ViewBuilder public func accentGlass() -> some View {
    if #available(iOS 26, macOS 26, *) {
      foregroundStyle(Ink.heroInk)
        .menuStyle(.button)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(.honey)
    } else {
      foregroundStyle(Ink.heroInk)
        .background(Color.honey, in: .circle)
        .overlay(Circle().strokeBorder(Ink.glassRim, lineWidth: GlassMetrics.rim))
    }
  }

  /// Solid, never glass, so it does not melt into the glass or the room.
  public func glassBadge(_ fill: Color = .honey) -> some View {
    foregroundStyle(Ink.heroInk)
      .background(fill, in: .capsule)
      .overlay(Capsule().strokeBorder(Ink.glassFill, lineWidth: 1.5))
  }
}

private struct RoleGlass<S: InsettableShape>: ViewModifier {
  let shape: S
  let role: GlassRole
  @Environment(\.glassRendering) private var rendering
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    surface(content).overlay {
      shape.strokeBorder(Ink.glassRim, lineWidth: GlassMetrics.rim).allowsHitTesting(false)
    }
  }

  @ViewBuilder private func surface(_ content: Content) -> some View {
    if rendering == .opaque {
      content.background {
        shape.fill(Ink.surface).shadow(color: .black.opacity(0.18), radius: 8, y: 3)
      }
    } else if rendering == .flat || reduceTransparency {
      content.background { shape.fill(Ink.surface) }
    } else if #available(iOS 26, macOS 26, *) {
      content.glassEffect(.regular.tint(Ink.glassFill).interactive(role == .control), in: shape)
    } else {
      content.background {
        shape.fill(.ultraThinMaterial).overlay { shape.fill(Ink.glassFill) }
      }
    }
  }
}

private struct GlassModifier<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?
  let clear: Bool
  let interactive: Bool
  @Environment(\.glassRendering) private var rendering

  func body(content: Content) -> some View {
    if rendering == .opaque {
      content
        .background { shape.fill(Ink.surface).shadow(color: .black.opacity(0.18), radius: 8, y: 3) }
        .overlay { shape.stroke(Ink.hairline, lineWidth: 1) }
    } else if rendering == .flat {
      content
        .background { shape.fill(Ink.surface) }
        .overlay { shape.stroke(Ink.hairline, lineWidth: 1) }
    } else if #available(iOS 26, macOS 26, *) {
      content.glassEffect(
        (clear ? Glass.clear : .regular).tint(tint).interactive(interactive), in: shape)
    } else {
      content.background(.ultraThinMaterial, in: shape)
    }
  }
}

extension View {
  /// A count, a dot or a small mark on a glass control's corner. A `GlassEffectContainer` draws its
  /// glass over everything inside it that is not glass, so in a `GlassGroup` the group draws the
  /// badge above itself, at this view's corner. Never hit-testable or read aloud: the control says it.
  public func glassControlBadge<Badge: View>(
    alignment: Alignment = .topTrailing, @ViewBuilder _ badge: () -> Badge
  ) -> some View {
    modifier(BadgeOverGlass(alignment: alignment, badge: AnyView(badge())))
  }
}

extension EnvironmentValues {
  @Entry fileprivate var liftsGlassBadges = false
}

private struct LiftedBadge {
  let bounds: Anchor<CGRect>
  let alignment: Alignment
  let view: AnyView
}

private struct LiftedBadges: PreferenceKey {
  static var defaultValue: [LiftedBadge] { [] }
  static func reduce(value: inout [LiftedBadge], nextValue: () -> [LiftedBadge]) {
    value += nextValue()
  }
}

private struct BadgeOverGlass: ViewModifier {
  let alignment: Alignment
  let badge: AnyView
  @Environment(\.liftsGlassBadges) private var lifts

  func body(content: Content) -> some View {
    if lifts {
      content.anchorPreference(key: LiftedBadges.self, value: .bounds) {
        [LiftedBadge(bounds: $0, alignment: alignment, view: badge)]
      }
    } else {
      content.overlay(alignment: alignment) {
        badge.allowsHitTesting(false).accessibilityHidden(true)
      }
    }
  }
}

/// One per bar: the glass in it is sampled together and morphs as one.
public struct GlassGroup<Content: View>: View {
  let spacing: CGFloat
  let content: Content
  @Environment(\.glassRendering) private var rendering

  public init(spacing: CGFloat = GlassMetrics.blend, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    if rendering != .liquid {
      content
    } else if #available(iOS 26, macOS 26, *) {
      GlassEffectContainer(spacing: spacing) { content.environment(\.liftsGlassBadges, true) }
        .overlayPreferenceValue(LiftedBadges.self) { badges in
          GeometryReader { proxy in
            ForEach(badges.indices, id: \.self) { index in
              let frame = proxy[badges[index].bounds]
              Color.clear
                .frame(width: frame.width, height: frame.height)
                .overlay(alignment: badges[index].alignment) { badges[index].view }
                .position(x: frame.midX, y: frame.midY)
            }
          }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
    } else {
      content
    }
  }
}

#Preview("Glass roles") {
  BothSchemes {
    GlassGroup {
      VStack(spacing: Space.l) {
        HStack(spacing: GlassMetrics.gap) {
          GlassSymbol(name: "tray.fill")
            .frame(width: Size.control, height: Size.control)
            .glass(.circle, role: .control)
          Text("Lv.3").font(.ourioMicro).padding(.horizontal, 7).frame(height: 17).glassBadge()
        }
        HStack(spacing: GlassMetrics.gap) {
          Text("Room").font(.ourioCallout.weight(.semibold)).foregroundStyle(Ink.glassGlyph)
            .padding(.horizontal, Space.l).frame(height: 36)
            .background(Ink.glassSelection, in: .capsule)
            .padding(Space.xs)
            .glass(.capsule, role: .bar)
          Button {
          } label: {
            Image(systemName: "plus").font(.title2.weight(.semibold))
          }
          .frame(width: 56, height: 56)
          .accentGlass()
        }
      }
    }
    .padding(Space.gutter)
    .background(RoomBackdrop())
  }
}
