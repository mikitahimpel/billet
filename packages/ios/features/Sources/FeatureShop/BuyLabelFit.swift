#if canImport(UIKit)
  import SwiftUI

  /// A buy button's words: one line, shrinking a little, until the accessibility sizes, where
  /// "Need 17 more" at full size is wider than any phone and wraps instead.
  struct BuyLabelFit: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
      content
        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
    }
  }

  extension View {
    func buyLabelFit() -> some View { modifier(BuyLabelFit()) }
  }
#endif
