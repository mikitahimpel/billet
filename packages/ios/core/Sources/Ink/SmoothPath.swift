import CoreGraphics
import Wire

/// A stroke's points as one smooth curve: quadratic segments through the midpoints of each pair
/// of points, so a batch of sparse points from the partner's phone does not draw as a polyline.
public enum SmoothPath {
  /// The curve through `points`, scaled from unit-square fractions by `scale` (the canvas width).
  public static func path(_ points: [Point], scale: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let scaled = points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
    guard let first = scaled.first else { return path }
    path.move(to: first)
    guard scaled.count > 2 else {
      // A dot, or a straight dash.
      path.addLine(to: scaled.last ?? first)
      return path
    }
    for index in 1..<(scaled.count - 1) {
      let control = scaled[index]
      let next = scaled[index + 1]
      path.addQuadCurve(
        to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2), control: control)
    }
    path.addLine(to: scaled[scaled.count - 1])
    return path
  }
}
