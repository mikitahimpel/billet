#if canImport(UIKit)
  import SwiftUI
  import UIKit

  /// Only the title text changes; the bars keep the system's own backgrounds.
  public enum NavigationBarStyle {
    /// About 20 ms to make on a cold launch.
    public struct Fonts: Sendable {
      public let large: UIFont
      public let inline: UIFont

      public nonisolated init() {
        large = NavigationBarStyle.rounded(size: 34, weight: .bold, style: .largeTitle)
        inline = NavigationBarStyle.rounded(size: 17, weight: .semibold, style: .headline)
      }
    }

    @MainActor private static var applied = false

    /// Once, at launch, off the main thread. The first bar comes with a sheet, which calls
    /// `apply()` in case it opens before the fonts are ready.
    @MainActor public static func prepare() {
      Task.detached(priority: .userInitiated) {
        let fonts = Fonts()
        await apply(fonts)
      }
    }

    /// Call before a navigation bar is made: a bar takes the appearance it finds then.
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
