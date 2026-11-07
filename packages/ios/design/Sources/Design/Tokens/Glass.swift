import SwiftUI

extension View {
  /// Liquid Glass from iOS 26, tinted when given one; earlier systems get a frosted material in the same shape.
  /// `clear` is the more see-through variant, for glass over the busy room.
  @ViewBuilder
  public func glass<S: Shape>(
    _ shape: S, tint: Color? = nil, clear: Bool = false, interactive: Bool = false
  ) -> some View {
    if #available(iOS 26, macOS 26, *) {
      glassEffect((clear ? Glass.clear : .regular).tint(tint).interactive(interactive), in: shape)
    } else {
      background(.ultraThinMaterial, in: shape)
    }
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

/// `GlassEffectContainer` from iOS 26; earlier systems show the content as is.
public struct GlassGroup<Content: View>: View {
  let spacing: CGFloat
  let content: Content

  public init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  public var body: some View {
    if #available(iOS 26, macOS 26, *) {
      GlassEffectContainer(spacing: spacing) { content }
    } else {
      content
    }
  }
}
