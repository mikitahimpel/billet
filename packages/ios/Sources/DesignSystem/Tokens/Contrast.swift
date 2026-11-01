import Foundation

/// The three floors every colour pair must clear.
public enum ContrastFloor: Double, CaseIterable, Sendable {
  case text = 4.5
  case mark = 3
  /// One interface rung against the next. Under this a card melts into the page.
  case rung = 1.15
}

/// WCAG 2.2 contrast.
public enum Contrast {
  public static func relativeLuminance(of swatch: Swatch) -> Double {
    func linear(_ channel: UInt8) -> Double {
      let value = Double(channel) / 255
      return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(swatch.red) + 0.7152 * linear(swatch.green) + 0.0722
      * linear(swatch.blue)
  }

  public static func ratio(_ first: Swatch, _ second: Swatch) -> Double {
    let (a, b) = (relativeLuminance(of: first), relativeLuminance(of: second))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }
}
