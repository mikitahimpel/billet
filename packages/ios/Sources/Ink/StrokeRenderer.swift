import CoreGraphics
import Wire

/// Draws unit-square strokes into a Core Graphics context, top-left origin.
public enum StrokeRenderer {
  public static func draw(
    _ strokes: [Stroke], in context: CGContext, size: CGSize
  ) throws(InkError) {
    context.saveGState()
    defer { context.restoreGState() }
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for stroke in strokes {
      guard let first = stroke.points.first else { continue }
      context.setStrokeColor(try parse(stroke.color))
      context.setLineWidth(stroke.width * size.width)
      context.beginPath()
      context.move(to: CGPoint(x: first.x * size.width, y: first.y * size.width))
      if stroke.points.count == 1 {
        context.addLine(to: CGPoint(x: first.x * size.width, y: first.y * size.width))
      }
      for point in stroke.points.dropFirst() {
        context.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.width))
      }
      context.strokePath()
    }
  }

  /// Parses `#RRGGBB`.
  static func parse(_ hex: String) throws(InkError) -> CGColor {
    guard InkColor.isValid(hex), let value = UInt32(hex.dropFirst(), radix: 16)
    else { throw InkError.invalidColor(hex) }
    let channel = { (shift: UInt32) in CGFloat((value >> shift) & 0xFF) / 255 }
    return CGColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
  }
}
