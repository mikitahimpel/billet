import SwiftUI

extension Font {
  // Text styles, so every size follows Dynamic Type: SF Rounded for display and controls, SF Pro for reading.
  public static let nookiLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
  public static let nookiTitle = Font.system(.title2, design: .rounded, weight: .bold)
  public static let nookiHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
  public static let nookiBody = Font.body
  public static let nookiCallout = Font.system(.subheadline, weight: .medium)
  public static let nookiCaption = Font.system(.footnote, weight: .medium)
  public static let nookiMicro = Font.system(.caption2, design: .rounded, weight: .semibold)
}
