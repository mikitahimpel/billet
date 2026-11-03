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
    draw(
      code, in: context, font: codeFont(size: codeSize(code)),
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

  /// The size the code is drawn at: as large as fits between the borders with a margin, measured
  /// rather than guessed from the count, so a long code never runs into the border.
  static func codeSize(_ code: String) -> Double {
    let width = measure(code, font: codeFont(size: 150))
    return width > 0 ? 150 * min(1, codeRoom / width) : 150
  }

  static func codeFont(size: Double) -> CTFont {
    font(BilletFonts.monoFamily, size: size, bold: true)
  }

  /// The width the code may take: inside the border, with a margin each side.
  static let codeRoom = Double(size.width) - 2 * 26 - 2 * 70

  /// How wide `text` is drawn in `font`, without the spacing after its last letter.
  static func measure(_ text: String, font: CTFont) -> Double {
    guard let line = line(text, font: font, colour: GenzColour(0)) else { return 0 }
    return CTLineGetTypographicBounds(line, nil, nil, nil) - kern(font)
  }

  private static func kern(_ font: CTFont) -> Double { CTFontGetSize(font) * 0.06 }

  private static func line(_ text: String, font: CTFont, colour: GenzColour) -> CTLine? {
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: font, kCTForegroundColorAttributeName: colour.cgColor,
      kCTKernAttributeName: kern(font),
    ]
    guard let string = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    else { return nil }
    return CTLineCreateWithAttributedString(string)
  }

  /// Draws `text` centred across `width`, its capitals centred on `centreY`. The spacing after the
  /// last letter is left out of the centring, or the line sits off to the left.
  private static func draw(
    _ text: String, in context: CGContext, font: CTFont, colour: GenzColour, centreY: Double,
    width: Double
  ) {
    guard let line = line(text, font: font, colour: colour) else { return }
    let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil) - kern(font)
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
