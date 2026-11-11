import SwiftUI

extension Font {
  // Text styles, so every size follows Dynamic Type: SF Rounded for display and controls, SF Pro for reading.
  public static let ourioLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
  public static let ourioTitle = Font.system(.title2, design: .rounded, weight: .bold)
  public static let ourioHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
  public static let ourioBody = Font.body
  public static let ourioCallout = Font.system(.subheadline, weight: .medium)
  public static let ourioCaption = Font.system(.footnote, weight: .medium)
  /// 12 pt, the smallest text in the app.
  public static let ourioMicro = Font.system(.caption, design: .rounded, weight: .semibold)
  /// A number or state that is the point of its card: a count, a streak.
  public static let ourioValue = Font.system(.title3, design: .rounded, weight: .bold)

  /// A hero number on a widget or a stat: fixed, because its frame is.
  public static let ourioNumber = Font.system(size: 52, weight: .heavy, design: .rounded)
}
