import SwiftUI

/// The corner scale, as a shape for clipping and as the container shape of what is inside.
public enum Corner: Sendable {
  case card
  case inner
  case control

  var radius: CGFloat {
    switch self {
    case .card: Radius.card
    case .inner: Radius.inner
    case .control: Radius.control
    }
  }
}

extension View {
  /// Clips to `corner` on the scale (docs/design-system.md#shape); feature code never writes a
  /// `RoundedRectangle` or a `cornerRadius` of its own.
  public func corners(_ corner: Corner) -> some View {
    let shape = RoundedRectangle(cornerRadius: corner.radius, style: .continuous)
    return clipShape(shape).containerShape(shape)
  }

  /// `style` drawn in the shape of `corner`, behind the view: a tile, a well, a selected cell.
  public func cornerFill(_ corner: Corner, _ style: some ShapeStyle) -> some View {
    background(style, in: RoundedRectangle(cornerRadius: corner.radius, style: .continuous))
      .containerShape(RoundedRectangle(cornerRadius: corner.radius, style: .continuous))
  }
}
