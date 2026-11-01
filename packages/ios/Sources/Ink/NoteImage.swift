import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Wire

/// The picture of a note: a square of transparent ink, and the App Group file of the latest one.
public enum NoteImage {
  public static let appGroup = "group.com.mikitahimpel.billet"
  private static let latestFileName = "latest-note.png"

  public static var latestFile: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent(latestFileName)
  }

  public static func cgImage(of strokes: [Stroke], side: Int = 480) -> CGImage? {
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

  /// Writes `strokes` as the latest note, and reports whether it did.
  @discardableResult
  public static func saveLatest(_ strokes: [Stroke], to file: URL? = latestFile) -> Bool {
    guard let file, let image = cgImage(of: strokes),
      let destination = CGImageDestinationCreateWithURL(
        file as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
  }

  public static func loadLatest(from file: URL? = latestFile) -> CGImage? {
    guard let file, let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// Scales and centres `strokes` to fill the unit square, because a drawing on the canvas can run
  /// taller than it is wide, or sit small in one corner. Thin lines thicken so they survive at
  /// lock-screen sizes.
  public static func fitted(_ strokes: [Stroke]) -> [Stroke] {
    let points = strokes.flatMap(\.points)
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
      let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
    else { return strokes }
    let margin = 0.08
    let thinnestStroke = 0.02
    let span = max(maxX - minX, maxY - minY, 0.05)
    let scale = (1 - 2 * margin) / span
    let offsetX = 0.5 - (minX + maxX) / 2 * scale
    let offsetY = 0.5 - (minY + maxY) / 2 * scale
    return strokes.map { stroke in
      Stroke(
        color: stroke.color,
        width: max(stroke.width * scale, thinnestStroke),
        points: stroke.points.map { Point(x: $0.x * scale + offsetX, y: $0.y * scale + offsetY) })
    }
  }
}
