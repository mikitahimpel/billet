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

extension View {
  /// Liquid Glass from iOS 26, tinted when given one; earlier systems get a frosted material in the same shape.
  /// `clear` is the more see-through variant, for glass over the busy room.
  public func glass<S: Shape>(
    _ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false
  ) -> some View {
    modifier(GlassModifier(shape: shape, tint: tint, clear: clear, interactive: interactive))
  }

  /// The see-through, honey-tinted glass for controls that float over the room.
  public func warmGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
    glass(shape, tint: Ink.glassTint, clear: true, interactive: interactive)
  }

  /// Warm glass behind a button's label that never takes a touch itself, so the button always gets it.
  public func warmGlassBacking<S: Shape>(_ shape: S) -> some View {
    background { Color.clear.warmGlass(shape).allowsHitTesting(false) }
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

/// `GlassEffectContainer` from iOS 26; earlier systems show the content as is.
public struct GlassGroup<Content: View>: View {
  let spacing: CGFloat
  let content: Content
  @Environment(\.glassRendering) private var rendering

  public init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
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
