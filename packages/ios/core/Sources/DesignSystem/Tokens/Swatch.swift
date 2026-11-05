import Foundation
import SwiftUI

/// An opaque sRGB colour, kept as numbers so contrast can be measured without a renderer.
public struct Swatch: Hashable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(_ hex: UInt32) {
    red = UInt8((hex >> 16) & 0xFF)
    green = UInt8((hex >> 8) & 0xFF)
    blue = UInt8(hex & 0xFF)
  }

  /// The `#RRGGBB` form stored in a stroke.
  public var hex: String {
    "#" + [red, green, blue].map { String(format: "%02X", $0) }.joined()
  }

  public var color: Color {
    Color(
      .sRGB,
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255
    )
  }

  /// This colour at `opacity`, flattened onto `ground`.
  public func composited(over ground: Swatch, opacity: Double) -> Swatch {
    func mix(_ top: UInt8, _ bottom: UInt8) -> UInt32 {
      UInt32((Double(top) * opacity + Double(bottom) * (1 - opacity)).rounded())
    }
    let hex =
      mix(red, ground.red) << 16 | mix(green, ground.green) << 8 | mix(blue, ground.blue)
    return Swatch(hex)
  }
}
