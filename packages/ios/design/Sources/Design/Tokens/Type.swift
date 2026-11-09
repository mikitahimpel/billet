import SwiftUI

extension Font {
  // Text styles, so every size follows Dynamic Type: SF Rounded for display and controls, SF Pro for reading.
  public static let ourioLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
  public static let ourioTitle = Font.system(.title2, design: .rounded, weight: .bold)
  public static let ourioHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
  public static let ourioBody = Font.body
  public static let ourioCallout = Font.system(.subheadline, weight: .medium)
  public static let ourioCaption = Font.system(.footnote, weight: .medium)
  public static let ourioMicro = Font.system(.caption2, design: .rounded, weight: .semibold)
}
