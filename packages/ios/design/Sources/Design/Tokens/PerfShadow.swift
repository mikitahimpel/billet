import SwiftUI

extension EnvironmentValues {
  /// Labs → Performance's Shadows switch; on as shipped.
  @Entry public var perfShadows = true
}

extension View {
  /// A shadow the lab's Shadows switch can take away.
  public func perfShadow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View
  {
    modifier(PerfShadow(color: color, radius: radius, x: x, y: y))
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
