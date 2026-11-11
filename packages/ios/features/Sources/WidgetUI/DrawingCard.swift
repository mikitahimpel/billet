import Design
import DrawInterface
import Ink
import SwiftUI
import Wire

/// A drawing on its wallpaper, scaled to fit whatever it is laid in: the widgets and their previews.
public struct DrawingCard: View {
  public let strokes: [Stroke]
  public let wallpaper: LockWallpaper
  /// Space kept clear around the drawing, as a fraction of the shorter side.
  public var margin = 0.1

  public init(strokes: [Stroke], wallpaper: LockWallpaper, margin: Double = 0.1) {
    self.strokes = strokes
    self.wallpaper = wallpaper
    self.margin = margin
  }

  public var body: some View {
    Canvas { context, size in
      for stroke in Self.fitted(strokes, in: size, margin: margin) {
        InkLayer.draw(stroke, in: &context, width: size.width)
      }
    }
    .allowsHitTesting(false)
    .background { LockWallpaperView(wallpaper: wallpaper) }
  }

  /// Scales and centres `strokes` (fractions of the sender's canvas width) into `size`, keeping their shape, and
  /// returns them as fractions of `size.width`, as `InkLayer` draws them. Thin lines keep a readable width.
  public static func fitted(_ strokes: [Stroke], in size: CGSize, margin: Double) -> [Stroke] {
    let points = strokes.flatMap(\.points)
    guard size.width > 0, size.height > 0,
      let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
      let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
    else { return strokes }
    let aspect = size.height / size.width
    let inset = margin * min(1, aspect)
    // The drawing's box, padded by half the widest line so round caps are not clipped.
    let pad = (strokes.map(\.width).max() ?? 0) / 2
    let spanX = max(maxX - minX + 2 * pad, 0.05)
    let spanY = max(maxY - minY + 2 * pad, 0.05)
    let scale = min((1 - 2 * inset) / spanX, (aspect - 2 * inset) / spanY)
    let offsetX = 0.5 - (minX + maxX) / 2 * scale
    let offsetY = aspect / 2 - (minY + maxY) / 2 * scale
    return strokes.map { stroke in
      Stroke(
        color: stroke.color, width: max(stroke.width * scale, 0.025),
        points: stroke.points.map { Point(x: $0.x * scale + offsetX, y: $0.y * scale + offsetY) })
    }
  }
}

extension LatestDrawing {
  /// The full strokes, or none if the compact rendition does not decode.
  public var strokes: [Stroke] { (try? InkDecoder.decode(compact)) ?? [] }
}
