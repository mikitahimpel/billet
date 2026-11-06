#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// SF Rounded navigation titles in `Ink.text`, for every navigation bar in the app. Only the title text
  /// changes; the bars keep the system's own backgrounds (glass on iOS 26). Call once at launch.
  public enum NavigationBarStyle {
    @MainActor
    public static func apply() {
      let bar = UINavigationBar.appearance()
      let text = UIColor(Ink.text)
      bar.largeTitleTextAttributes = [
        .font: rounded(size: 34, weight: .bold, style: .largeTitle), .foregroundColor: text,
      ]
      bar.titleTextAttributes = [
        .font: rounded(size: 17, weight: .semibold, style: .headline), .foregroundColor: text,
      ]
    }

    /// SF Rounded at the text style's default size, scaled by Dynamic Type.
    private static func rounded(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle)
      -> UIFont
    {
      let system = UIFont.systemFont(ofSize: size, weight: weight)
      let font =
        system.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) }
        ?? system
      return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
  }
#endif
