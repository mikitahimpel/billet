#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// SF Rounded navigation titles in `Ink.text`, for every navigation bar in the app. Only the title text
  /// changes; the bars keep the system's own backgrounds (glass on iOS 26).
  public enum NavigationBarStyle {
    /// The two title fonts, about 20 ms to make on a cold launch.
    public struct Fonts: Sendable {
      public let large: UIFont
      public let inline: UIFont

      public nonisolated init() {
        large = NavigationBarStyle.rounded(size: 34, weight: .bold, style: .largeTitle)
        inline = NavigationBarStyle.rounded(size: 17, weight: .semibold, style: .headline)
      }
    }

    @MainActor private static var applied = false

    /// Once, at launch: makes the fonts off the main thread and sets them when they are ready. No bar is on the
    /// first screen; the first comes with a sheet, which calls `apply()` in case it opens before they are.
    @MainActor public static func prepare() {
      Task.detached(priority: .userInitiated) {
        let fonts = Fonts()
        await apply(fonts)
      }
    }

    /// Sets the fonts now if they are not set yet. Call before a navigation bar is made: a bar takes the
    /// appearance it finds then.
    @MainActor public static func apply() {
      if !applied { apply(Fonts()) }
    }

    @MainActor private static func apply(_ fonts: Fonts) {
      guard !applied else { return }
      applied = true
      let bar = UINavigationBar.appearance()
      let text = UIColor(Ink.text)
      bar.largeTitleTextAttributes = [.font: fonts.large, .foregroundColor: text]
      bar.titleTextAttributes = [.font: fonts.inline, .foregroundColor: text]
    }

    /// SF Rounded at the text style's default size, scaled by Dynamic Type.
    nonisolated static func rounded(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle)
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
