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

  /// `image` cropped to the box around its ink, or unchanged if it has none.
  public static func trimmedToInk(_ image: CGImage) -> CGImage {
    let (width, height) = (image.width, image.height)
    var alpha = [UInt8](repeating: 0, count: width * height)
    let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return image }
    var (left, right, top, bottom) = (width, -1, height, -1)
    for y in 0..<height {
      for x in 0..<width where alpha[y * width + x] > 0 {
        left = min(left, x)
        right = max(right, x)
        top = min(top, y)
        bottom = max(bottom, y)
      }
    }
    guard right >= left, bottom >= top else { return image }
    return image.cropping(
      to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? image
  }

  /// Reports whether it wrote.
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

  public static func removeLatest(at file: URL? = latestFile) {
    guard let file else { return }
    try? FileManager.default.removeItem(at: file)
  }

  /// A canvas drawing can run taller than wide or sit small in a corner. Thin lines thicken so
  /// they survive at lock-screen sizes.
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
