import CoreGraphics
import Wire

/// Renders a finished drawing on its own, for anywhere a note is shown as a picture.
public enum NoteImage {
  /// `strokes` on a transparent square, fitted so the drawing fills it.
  public static func render(_ strokes: [Stroke], side: Int) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let size = CGSize(width: side, height: side)
    guard (try? StrokeRenderer.draw(fitted(strokes), in: context, size: size)) != nil else {
      return nil
    }
    return context.makeImage()
  }

  /// Scales and centres `strokes` to fill the unit square, because a drawing on the canvas can run
  /// taller than it is wide, or sit small in one corner.
  public static func fitted(_ strokes: [Stroke]) -> [Stroke] {
    let points = strokes.flatMap(\.points)
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
      let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
    else { return strokes }
    let margin = 0.08
    let span = max(maxX - minX, maxY - minY, 0.05)
    let scale = (1 - 2 * margin) / span
    let offsetX = 0.5 - (minX + maxX) / 2 * scale
    let offsetY = 0.5 - (minY + maxY) / 2 * scale
    return strokes.map { stroke in
      Stroke(
        color: stroke.color,
        width: stroke.width * scale,
        points: stroke.points.map { Point(x: $0.x * scale + offsetX, y: $0.y * scale + offsetY) })
    }
  }
}
