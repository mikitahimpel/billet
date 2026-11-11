import Design
import Ink
import SwiftUI
import Wire

/// Strokes drawn as a `Marker`. Coordinates and widths are fractions of the layer's width, as
/// strokes carry them, so the same drawing fills any phone.
public struct InkLayer: View {
  public let strokes: [Stroke]

  public init(strokes: [Stroke]) {
    self.strokes = strokes
  }

  public var body: some View {
    Canvas { context, size in
      for stroke in strokes {
        InkLayer.draw(stroke, in: &context, width: size.width)
      }
    }
    .allowsHitTesting(false)
  }

  public static func draw(_ stroke: Stroke, in context: inout GraphicsContext, width: CGFloat) {
    guard !stroke.points.isEmpty, let color = Color(drawnInk: stroke.color) else { return }
    Marker.draw(
      Path(SmoothPath.path(stroke.points, scale: width)), color: color,
      width: stroke.width * width, in: &context)
  }
}
