import SwiftUI

extension EnvironmentValues {
  /// Labs → Performance's switches the pages read; each is on as shipped.
  @Entry public var perfShadows = true
  @Entry public var perfShine = true
  @Entry public var perfFlatten = false
}

extension View {
  /// A shadow the lab's Shadows switch can take away.
  public func perfShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View
  {
    modifier(PerfShadow(color: color, radius: radius, x: x, y: y))
  }

  /// Drawn into one layer while the lab's Flatten switch is on.
  public func perfFlattened() -> some View { modifier(PerfFlatten()) }
}

private struct PerfFlatten: ViewModifier {
  @Environment(\.perfFlatten) private var flatten

  @ViewBuilder func body(content: Content) -> some View {
    if flatten { content.drawingGroup() } else { content }
  }
}

private struct PerfShadow: ViewModifier {
  let color: Color
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat
  @Environment(\.perfShadows) private var shows

  func body(content: Content) -> some View {
    content.shadow(color: shows ? color : .clear, radius: shows ? radius : 0, x: x, y: y)
  }
}
