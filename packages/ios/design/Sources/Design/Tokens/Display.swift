import SwiftUI

extension Font {
  /// The lock-screen clock and its date line, drawn at a fixed size like the system's own.
  public static let nookiClock = Font.system(size: 104, weight: .light, design: .rounded)
  public static let nookiClockDate = Font.system(size: 21, weight: .semibold, design: .rounded)
}
