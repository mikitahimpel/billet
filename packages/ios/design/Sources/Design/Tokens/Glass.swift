import SwiftUI

/// How the glass controls are drawn: Liquid Glass; an opaque surface of the same shape with a
/// stroke and a shadow; or that surface flat, with no shadow. The arms a perf run measures the
/// glass against (`-perf.hud opaque|flat`); neither opaque arm uses a `GlassEffectContainer`.
public enum GlassRendering: Sendable {
  case liquid
  case opaque
  case flat
}

extension EnvironmentValues {
  @Entry public var glassRendering: GlassRendering = .liquid
}

/// The one glass of the app. Every floating surface picks a role; the role fixes everything else.
///
/// | Role | Glass | Tint | Rim | Shadow | Ink |
/// | --- | --- | --- | --- | --- | --- |
/// | `control` | regular, interactive | `Ink.glassFill` | 1 pt `Ink.glassRim` | the system's own | `Ink.glassGlyph` |
/// | `bar` | regular | `Ink.glassFill` | 1 pt `Ink.glassRim` | the system's own | `Ink.glassGlyph`, unselected `glassGlyphSecondary`, selected on `Ink.glassSelection` |
/// | `accent` | prominent, interactive | honey | the system's own | the system's own | `Ink.heroInk` |
///
/// A badge on a glass surface is not glass (`glassBadge`). With Reduce Transparency the tint is drawn
/// solid as `Ink.surface`; the system frosts native glass the same way.
public enum GlassRole: Sendable {
  /// One control: a round header button, the coin pill, the pet, a label over the scene.
  case control
  /// A surface holding several controls that respond themselves: the tab bar, the Room | City switch.
  case bar
}

/// The distance under which shapes in one `GlassGroup` melt into each other. Every group uses it and every
/// row of glass keeps a wider gap, so neighbours morph when they appear but never merge at rest.
public enum GlassMetrics {
  public static let blend: CGFloat = Space.s
  /// The gap between two glass surfaces in a row.
  public static let gap: CGFloat = Space.s + 2
  public static let rim: CGFloat = 1
}

extension View {
  /// The app's glass in `shape` for `role`. Apply it after the content's other modifiers: it captures them.
  public func glass<S: InsettableShape>(_ shape: S, role: GlassRole) -> some View {
    modifier(RoleGlass(shape: shape, role: role))
  }

  /// Liquid Glass from iOS 26, tinted when given one; earlier systems get a frosted material in the same shape.
  /// `clear` is the more see-through variant. For art inside content and full-screen canvases; chrome uses
  /// `glass(_:role:)`.
  public func glass<S: Shape>(
    _ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false
  ) -> some View {
    modifier(GlassModifier(shape: shape, tint: tint, clear: clear, interactive: interactive))
  }

  /// The see-through, honey-tinted glass of a full-screen canvas's tools.
  public func warmGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
    glass(shape, tint: Ink.glassTint, clear: true, interactive: interactive)
  }

  /// The `accent` role on a button or menu: the one main action beside a bar, honey prominent glass.
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

  /// A badge on the corner of a glass surface: a solid capsule ringed in the glass's own colour, so it never
  /// melts into the glass or the room. Never glass itself.
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

/// `GlassEffectContainer` from iOS 26; earlier systems show the content as is. One per bar: the glass in it is
/// sampled together and morphs as one.
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
      GlassEffectContainer(spacing: spacing) { content }
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
