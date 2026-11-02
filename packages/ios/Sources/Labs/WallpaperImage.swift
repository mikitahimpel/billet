import CoreGraphics
import DesignSystem
import Foundation
import Ink
import Wire

/// A phone-sized picture of the partner's latest note on the night sky, for a wallpaper.
public enum WallpaperImage {
  public static let size = CGSize(width: 1170, height: 2532)

  /// Where the note sits. The top quarter stays clear for the Lock Screen clock, and the note is
  /// centred in what is left above the hill.
  static func noteRect(in size: CGSize) -> CGRect {
    let side = size.width * 0.7
    let top = size.height * 0.3
    let bottom = size.height * 0.86
    return CGRect(
      x: (size.width - side) / 2, y: top + (bottom - top - side) / 2, width: side, height: side)
  }

  public static func render(strokes: [Stroke], size: CGSize = size) -> CGImage? {
    render(note: NoteImage.cgImage(of: strokes, side: 1024), size: size)
  }

  /// - Parameter note: The drawing as transparent ink on a square, or nil for the sky alone.
  public static func render(note: CGImage?, size: CGSize = size) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Core Graphics counts up from the bottom; flip so the layout below reads top-down.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    drawSky(in: context, size: size)
    drawHill(in: context, size: size)
    if let note { drawNote(note, in: context, size: size) }
    return context.makeImage()
  }

  private static func color(_ swatch: Swatch, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
      srgbRed: CGFloat(swatch.red) / 255, green: CGFloat(swatch.green) / 255,
      blue: CGFloat(swatch.blue) / 255, alpha: alpha)
  }

  private static func drawSky(in context: CGContext, size: CGSize) {
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(
      colorsSpace: space,
      colors: [color(Palette.skyNight), color(Palette.sky), color(Palette.skyLit)] as CFArray,
      locations: [0, 0.6, 1])
    {
      context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }
    // The same stars every time, from a fixed recurrence rather than random numbers.
    var seed: UInt64 = 7
    for _ in 0..<70 {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let x = Double(seed >> 33 & 0xFFFF) / 65_535 * size.width
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let y = Double(seed >> 33 & 0xFFFF) / 65_535 * size.height * 0.7
      let radius = 2 + Double(seed >> 20 & 3)
      context.setFillColor(color(Palette.lightWarm, 0.55))
      context.fillEllipse(
        in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }
    context.setFillColor(color(Palette.light, 0.9))
    context.fillEllipse(
      in: CGRect(x: size.width * 0.68, y: size.height * 0.14, width: 110, height: 110))
  }

  private static func drawHill(in context: CGContext, size: CGSize) {
    context.setFillColor(color(Palette.hill))
    context.move(to: CGPoint(x: 0, y: size.height * 0.9))
    context.addCurve(
      to: CGPoint(x: size.width, y: size.height * 0.86),
      control1: CGPoint(x: size.width * 0.3, y: size.height * 0.84),
      control2: CGPoint(x: size.width * 0.7, y: size.height * 0.92))
    context.addLine(to: CGPoint(x: size.width, y: size.height))
    context.addLine(to: CGPoint(x: 0, y: size.height))
    context.closePath()
    context.fillPath()
  }

  private static func drawNote(_ note: CGImage, in context: CGContext, size: CGSize) {
    let rect = noteRect(in: size)
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.rotate(by: -0.03)
    let local = CGRect(
      x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
    context.setShadow(offset: .zero, blur: 70, color: color(Palette.light, 0.35))
    let paper = CGPath(roundedRect: local, cornerWidth: 36, cornerHeight: 36, transform: nil)
    context.setFillColor(color(Palette.paper))
    context.addPath(paper)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)
    // The note image is drawn upright: undo the flip for the picture itself.
    context.translateBy(x: 0, y: 0)
    context.scaleBy(x: 1, y: -1)
    context.draw(note, in: local.insetBy(dx: 28, dy: 28))
    context.restoreGState()
  }
}
