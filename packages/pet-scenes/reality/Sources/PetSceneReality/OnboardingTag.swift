import CoreGraphics
import CoreText
import DesignSystem
import Foundation

/// The face of the first-launch tag: warm paper with a small heart, "our code", and the pair's
/// code large in the app's monospaced face.
enum OnboardingTag {
  static let size = (width: 1024, height: 492)

  static func image(code: String) -> CGImage? {
    let (width, height) = size
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(GenzColour(0xFFF6EA).cgColor)
    context.fill(bounds)
    // A thin inked border, inset like a printed card.
    context.setStrokeColor(GenzColour(0xD9A88E).cgColor)
    context.setLineWidth(6)
    context.stroke(bounds.insetBy(dx: 26, dy: 26))
    heart(in: context, centre: CGPoint(x: Double(width) / 2, y: Double(height) - 92), size: 52)
    draw(
      "our code", in: context, font: font(BilletFonts.monoFamily, size: 40),
      colour: GenzColour(0xB0705A), centreY: Double(height) - 160, width: Double(width))
    let codeSize = min(150, 1.55 * Double(width - 120) / Double(max(code.count, 1)))
    draw(
      code, in: context, font: font(BilletFonts.monoFamily, size: codeSize, bold: true),
      colour: GenzColour(0x5A2E26), centreY: Double(height) * 0.36, width: Double(width))
    return context.makeImage()
  }

  private static func font(_ family: String, size: Double, bold: Bool = false) -> CTFont {
    var traits: [CFString: Any] = [:]
    if bold { traits[kCTFontWeightTrait] = 0.4 }
    let descriptor = CTFontDescriptorCreateWithAttributes(
      [kCTFontFamilyNameAttribute: family, kCTFontTraitsAttribute: traits] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, size, nil)
  }

  private static func draw(
    _ text: String, in context: CGContext, font: CTFont, colour: GenzColour, centreY: Double,
    width: Double
  ) {
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: font, kCTForegroundColorAttributeName: colour.cgColor,
      kCTKernAttributeName: CTFontGetSize(font) * 0.06,
    ]
    guard let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    else { return }
    let line = CTLineCreateWithAttributedString(string)
    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(
      x: (width - lineWidth) / 2, y: centreY - CTFontGetCapHeight(font) / 2)
    CTLineDraw(line, context)
  }

  private static func heart(in context: CGContext, centre: CGPoint, size: Double) {
    let path = CGMutablePath()
    let top = CGPoint(x: centre.x, y: centre.y + size * 0.3)
    path.move(to: CGPoint(x: centre.x, y: centre.y - size * 0.55))
    path.addCurve(
      to: top, control1: CGPoint(x: centre.x - size * 0.95, y: centre.y + size * 0.05),
      control2: CGPoint(x: centre.x - size * 0.45, y: centre.y + size * 0.85))
    path.addCurve(
      to: CGPoint(x: centre.x, y: centre.y - size * 0.55),
      control1: CGPoint(x: centre.x + size * 0.45, y: centre.y + size * 0.85),
      control2: CGPoint(x: centre.x + size * 0.95, y: centre.y + size * 0.05))
    context.addPath(path)
    context.setFillColor(GenzColour(0xE8475E).cgColor)
    context.fillPath()
  }
}
